{ lib
, python3
, fetchPypi
}:
python3.pkgs.buildPythonApplication rec {
  pname = "ddcci-plasmoid-backend";
  version = "0.1.8";
  format = "pyproject";

  src = fetchPypi {
    pname = "ddcci_plasmoid_backend";
    inherit version;
    hash = "sha256-tA2eg8iknuFBHsj4HLXyQBrEK5LSTF0z2hRx2lXl6CE=";
  };

  nativeBuildInputs = with python3.pkgs; [
    poetry-core
    # pytestCheckHook
  ];

  propagatedBuiltInputs = with python3.pkgs; [
    tox
  ];

  doCheck = false; # skip check because backend/fixtures/basic/indented.txt not included in pypi source package
  nativeCheckInputs = with python3.pkgs; [
    pytest-asyncio
  ];

  pythonImportsCheck = [
    "ddcci_plasmoid_backend"
  ];
}
