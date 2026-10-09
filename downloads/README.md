# downloads/

Place the NKP CLI for **Linux amd64** here as `downloads/nkp`. The toolkit copies it
to the jump host; it is not included in this repository.

1. Download the NKP v2.18.0 CLI bundle for Linux amd64 from the
   [Nutanix Support Portal](https://portal.nutanix.com/) under your own entitlement.
2. Extract it and copy the `nkp` executable to this directory:

   ```bash
   tar -xzf nkp_v2.18.0_linux_amd64.tar.gz
   cp nkp downloads/nkp   # adjust the source path to where the archive extracted it
   chmod +x downloads/nkp
   ```

3. Compare the checksums with the values in your `inventory.ini`
   (`nkp_binary_md5`, `nkp_binary_sha256`):

   ```bash
   sha256sum downloads/nkp   # macOS: shasum -a 256 downloads/nkp
   md5sum downloads/nkp      # macOS: md5 downloads/nkp
   ```

The values shipped in `inventory.example.ini` were computed by the author on the
v2.18.0 linux/amd64 CLI:

| Algorithm | Value |
|---|---|
| MD5 | `deeb16aa4cf913e44222b67f97335888` |
| SHA-256 | `984259bf0efb56ab8ac08f96f1ba9f1e32080af94fd0b82b8a71ffd1501ff564` |

The authoritative checksums are those published by Nutanix. For any other build,
update the two variables in `inventory.ini`. The preflight stage
(`./deploy.sh check`) stops if the file is missing or a checksum differs.

Everything in this directory except this file and `.gitkeep` is ignored by git.
Vendor files placed here are never committed.
