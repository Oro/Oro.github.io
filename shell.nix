# See https://kalbas.it/2019/02/26/manage-a-static-website-with-hugo-and-nix/ for further info
{ pkgs ? import <nixpkgs> {} }:
with pkgs;
mkShell {
  buildInputs = [
    hugo
  ];
}
