# git-sync
Git-Sync helps you sync your repositories across multiple remotes.

The main goal of this script is to create enough redundancy so even if a single provider will fail you can still access your code using alternative hosting companies.

## How to use
### 1. Generate SSH key
```bash
cd c:\Users\Alan\.ssh\
ssh-keygen.exe
notepad.exe id_rsa.pub
```

### 2. Add SSH keys to your alternate hosting websites
Go to you repository hosting website and add key generated in previous step.

Here are some examples:

- `https://[USER_NAME].visualstudio.com/_details/security/keys`
- `https://bitbucket.org/account/user/[USER_NAME]/ssh-keys/`
- `https://github.com/settings/keys`

### 3. Create configuration
- Rename `config-example.json` into `config.json`
- Add your configuration

### 4. Run script

```powershell
.\sync.ps1
```

## License
[MIT](LICENSE)