# downloads/

Place the NKP CLI bundle for **Linux amd64** here, exactly as downloaded from the
Nutanix Support Portal: `downloads/nkp_v2.18.0_linux_amd64.tar.gz`. Do not extract
it. The toolkit verifies it, copies it to the jump host and installs the CLI from
it; the bundle is not included in this repository.

1. On the [Nutanix Support Portal](https://portal.nutanix.com/), under your own
   entitlement, download the NKP v2.18.0 CLI bundle for Linux amd64 and note the
   **SHA-256** the portal shows next to the file.
2. Save the file in this directory with its original name.
3. In `inventory.ini` set the release and that SHA-256:

   ```ini
   nkp_version = 2.18.0
   nkp_archive_sha256 = <the SHA-256 shown by the portal>
   ```

   `inventory.example.ini` carries the value the portal showed on 2026-10-10. If the
   portal shows another value for the same file name, the portal wins: Nutanix has
   republished a release under the same version with a rebuilt executable.

The preflight stage (`./deploy.sh check`) stops when the file is missing, when its
SHA-256 differs from `nkp_archive_sha256`, or when it does not contain an `nkp`
executable at its top level (for example the macOS bundle). The jump host stage
installs the executable under `/usr/local/lib/nkp/<nkp_version>/`, points
`/usr/local/bin/nkp` at it and checks that `nkp version` reports `nkp: v<nkp_version>`.

Another release goes next to this one: add its bundle here, set `nkp_version` and
`nkp_archive_sha256` to its values and run the jump host stage again. The previous
release stays installed under its own directory.

To check the file yourself:

```bash
sha256sum downloads/nkp_v2.18.0_linux_amd64.tar.gz   # macOS: shasum -a 256 <file>
tar -tzf downloads/nkp_v2.18.0_linux_amd64.tar.gz    # lists NOTICES and nkp
```

Everything in this directory except this file and `.gitkeep` is ignored by git.
Vendor files placed here are never committed.
