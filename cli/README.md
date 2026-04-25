# FastShared CLI

Command-line uploader for FastShared.

```bash
fastshared ./report.pdf
fastshared ./screenshots
fastshared - --name output.txt
fastshared ./trace.log --ttl 60s --json
```

Default output is the share URL only, which makes it safe for scripts and AI agents:

```bash
url="$(fastshared ./artifact.zip)"
```

