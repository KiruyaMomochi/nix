{ lib
, buildPythonPackage
, fetchPypi
, setuptools-scm
, setuptools
, pyyaml
, requirements-parser
, jsonschema
, bindep
}: buildPythonPackage rec {
  pname = "ansible-builder";
  version = "3.0.0";
  pyproject = true;

  patches = [
    ./setuptools-no-upper.patch
  ];

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-IY1U3cPOm4Swus8nqZebBDbKLOAoigAC7XjCUqVh2l0=";
  };

  nativeBuildInputs = [
    setuptools-scm
  ];

  propagatedBuildInputs = [
    setuptools
    pyyaml
    requirements-parser
    bindep
    jsonschema
  ];

  pythonImportsCheck = [
    "ansible_builder"
    "ansible_builder.cli"
  ];

  meta = with lib; {
    changelog = "https://github.com/ansible/ansible-builder/releases/tag/${version}";
    description = "An Ansible execution environment builder";
    homepage = "https://github.com/ansible/ansible-builder";
    license = licenses.asl20;
  };
}
