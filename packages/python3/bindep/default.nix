{ lib
, buildPythonPackage
, fetchPypi
, setuptools
, distro
, pbr
, parsley
, packaging
, pythonOlder
, stestr
, fixtures
, mock
, subunit
, testtools
}:

buildPythonPackage rec {
  pname = "bindep";
  version = "2.11.0";
  format = "setuptools";

  disabled = pythonOlder "3.6";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-rLLyWbzh/RUIhzR5YJu95bmq5Qg3hHamjWtqGQAufi8=";
  };

  nativeBuildInputs = [
    setuptools
  ];

  propagatedBuildInputs = [
    pbr
    distro
    parsley
    packaging
  ];

  nativeCheckInputs = [
    stestr
    fixtures
    mock
    subunit
    testtools
  ];

  pythonImportsCheck = [
    "bindep"
  ];


  # `stestr run --test-path ./bindep/tests` fails with distro test
  doCheck = false;

  meta = with lib; {
    changelog = "https://docs.opendev.org/opendev/bindep/latest/releasenotes.html";
    description = "Binary dependency utility";
    homepage = "https://docs.opendev.org/opendev/bindep";
    license = licenses.asl20;
    maintainers = [ ];
  };
}
