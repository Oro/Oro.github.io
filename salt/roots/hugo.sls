hugo-install:
  pkg.installed:
    - sources: 
        - hugo: https://github.com/spf13/hugo/releases/download/v0.15/hugo_0.15_amd64.deb

utils.install:
  pkg.installed:
    - names:
        - git
        - python-psutil

hugo-server-absent:
  process.absent:
    - name: hugo

hugo-server-start:
  cmd.run:
    - name: 'nohup hugo server --bind="0.0.0.0" --theme=blackburn --buildDrafts --baseUrl=172.17.0.100 >/var/log/hugo 2>&1 &'
    - cwd: /var/hugo/
