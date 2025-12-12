{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "ghstack";
  version = "0.12.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "ezyang";
    repo = "ghstack";
    rev = "fa7e7023d798aad6b115b88c5ad67ce88a4fc2a6";
    hash = "sha256-Ywwjeupa8eE/vkrbl5SIbvQs53xaLnq9ieWRFwzmuuc=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["uv_build>=0.6,<0.7"]' 'requires = ["uv_build>=0.6"]'
  '';

  build-system = [ python3.pkgs.uv-build ];

  dependencies = with python3.pkgs; [
    aiohttp
    click
    flake8
    importlib-metadata
    requests
    typing-extensions
  ];

  pythonImportsCheck = [ "ghstack.cli" ];

  meta = {
    description = "Submit stacked diffs to GitHub on the command line";
    homepage = "https://github.com/ezyang/ghstack";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      munksgaard
      shikanime
    ];
    mainProgram = "ghstack";
  };
}
