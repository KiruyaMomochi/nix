# Howdy recorder for the Vivobook S15's HM1092 IR sensor behind Qualcomm CAMSS.
#
# OpenCV can't read CAMSS (multiplanar nodes, packed RAW10), and libcamera's
# software ISP would debayer this monochrome sensor because the driver tags it
# SGRBG10. So take the Raw stream from libcamera and unpack it ourselves.
# The IR flood LED is a PMIC flash LED with no link to the sensor, so we turn
# it on for the capture and off on release.

import atexit
import mmap
import os
import selectors
import sys
import time

import numpy

from cv2 import CAP_PROP_FRAME_WIDTH, CAP_PROP_FRAME_HEIGHT

os.environ.setdefault("LIBCAMERA_LOG_LEVELS", "*:FATAL")
sys.path.insert(0, "@libcameraPython@")
import libcamera

# Under PAM, sudo is ruid=user/euid=root, so libcamera's secure_getenv() ignores
# LIBCAMERA_LOG_LEVELS and its INFO/WARN spew lands in the terminal. Silence fd 2.
if os.getuid() != os.geteuid():
	os.dup2(os.open(os.devnull, os.O_WRONLY), 2)

LED = "/sys/class/leds/ir:flash/brightness"


def _led(value):
	try:
		with open(LED, "w") as f:
			f.write(str(value))
	except OSError:
		pass


class ir_reader:
	def __init__(self, timeout=3.0):
		self.timeout = timeout
		self._cm = libcamera.CameraManager.singleton()
		self._camera = next((c for c in self._cm.cameras
			if "hm1092" in str(c.properties.get(libcamera.properties.Model, "")).lower()), None)
		if self._camera is None:
			print("Howdy could not find the HM1092 IR camera (is another app using the camera?)")
			sys.exit(14)

		self._camera.acquire()
		config = self._camera.generate_configuration([libcamera.StreamRole.Raw])
		sc = config.at(0)
		config.validate()
		self._camera.configure(config)
		self._stream = sc.stream
		self._w, self._h, self._stride = sc.size.width, sc.size.height, sc.stride

		self._alloc = libcamera.FrameBufferAllocator(self._camera)
		self._alloc.allocate(self._stream)
		self._maps = {}
		requests = []
		for buffer in self._alloc.buffers(self._stream):
			plane = buffer.planes[0]
			self._maps[buffer] = (mmap.mmap(plane.fd, plane.offset + plane.length,
				mmap.MAP_SHARED, mmap.PROT_READ), plane.offset)
			request = self._camera.create_request()
			request.add_buffer(self._stream, buffer)
			requests.append(request)

		# compare.py sys.exit()s without releasing; __del__ then runs after builtins
		# are gone and the LED would stay on.
		atexit.register(self.release)
		_led(255)
		self._camera.start()
		self._started = True
		for request in requests:
			self._camera.queue_request(request)
		self._selector = selectors.DefaultSelector()
		self._selector.register(self._cm.event_fd, selectors.EVENT_READ)

	def _unpack(self, raw):
		# RAW10 CSI-2 packed: 4 pixels in 5 bytes, the 5th holds the low 2 bits.
		# The module is mounted upside down, hence the flip.
		b = raw.reshape(self._h, self._stride)[:, :self._w * 5 // 4] \
			.reshape(self._h, self._w // 4, 5).astype(numpy.uint16)
		px = numpy.empty((self._h, self._w // 4, 4), numpy.uint16)
		for i in range(4):
			px[:, :, i] = (b[:, :, i] << 2) | ((b[:, :, 4] >> (2 * i)) & 3)
		px = px.reshape(self._h, self._w)[::-1, ::-1].astype(numpy.float32)
		# Stretch lit frames, but keep a floor so unlit ones stay dark instead of turning into noise.
		hi = max(numpy.percentile(px, 99.5), 256.0)
		grey = numpy.clip(px * (255.0 / hi), 0, 255).astype(numpy.uint8)
		return numpy.repeat(grey[:, :, None], 3, axis=2)

	def _read_frame(self):
		deadline = time.monotonic() + self.timeout
		while time.monotonic() < deadline:
			if not self._selector.select(timeout=0.5):
				continue
			frame = None
			for request in self._cm.get_ready_requests():
				buffer = request.buffers.get(self._stream)
				if buffer in self._maps:
					mapping, offset = self._maps[buffer]
					frame = self._unpack(numpy.frombuffer(mapping, numpy.uint8,
						count=self._stride * self._h, offset=offset))
				request.reuse()
				self._camera.queue_request(request)
			if frame is not None:
				return frame
		return None

	def read(self):
		frame = self._read_frame()
		return (frame is not None), frame

	def grab(self):
		return self._read_frame() is not None

	def set(self, prop, value):
		pass

	def get(self, prop):
		if prop == CAP_PROP_FRAME_WIDTH:
			return self._w
		if prop == CAP_PROP_FRAME_HEIGHT:
			return self._h
		return 0

	def release(self):
		if not getattr(self, "_started", False):
			return
		self._started = False
		_led(0)
		try:
			self._camera.stop()
			self._camera.release()
		except Exception:
			pass
		for mapping, _ in self._maps.values():
			mapping.close()
		self._maps = {}

	def __del__(self):
		self.release()
