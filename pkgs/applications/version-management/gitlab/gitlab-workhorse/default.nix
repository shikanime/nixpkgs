{ lib, fetchFromGitLab, git, buildGoModule }:
let
  data = lib.importJSON ../data.json;
in
buildGoModule rec {
  pname = "gitlab-workhorse";

  version = "14.10.2";

  src = fetchFromGitLab {
    owner = data.owner;
    repo = data.repo;
    rev = data.rev;
    sha256 = data.repo_hash;
  };

  sourceRoot = "source/workhorse";

  vendorSha256 = "sha256-TNZtggUBMwIPO6ZZGk/EkRcilh7sztlAT7Hu4vhME0w=";
  buildInputs = [ git ];
  ldflags = [ "-X main.Version=${version}" ];
  doCheck = false;

  meta = with lib; {
    homepage = "http://www.gitlab.com/";
    platforms = platforms.linux;
    maintainers = with maintainers; [ fpletz globin talyz yayayayaka ];
    license = licenses.mit;
  };
}
