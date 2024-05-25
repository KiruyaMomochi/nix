{ lib
, python3
, fetchPypi
}:
python3.pkgs.buildPythonApplication rec {
  pname = "ddcci-plasmoid-backend";
  version = "0.1.10";
  format = "pyproject";

  src = fetchPypi {
    pname = "ddcci_plasmoid_backend";
    inherit version;
    hash = "sha256-95dGkZqlaxwBiy7LXjTW83D8qVUEFUL5Nely9lzMAzo=";
  };

  nativeBuildInputs = with python3.pkgs; [
    poetry-core
    pythonRelaxDepsHook
    # pytestCheckHook
  ];

  pythonRelaxDeps = [
    "fasteners"
  ];

  propagatedBuildInputs = with python3.pkgs; [
    fasteners
  ];

  doCheck = true; # fasteners<0.19,>=0.18 not satisfied by version 0.19
  nativeCheckInputs = with python3.pkgs; [
    pytest-asyncio
    tox
  ];

  pythonImportsCheck = [
    "ddcci_plasmoid_backend"
  ];
}
