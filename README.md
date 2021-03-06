# git-sync
Git-Sync helps you sync your repositories across multiple remotes.

The main goal of this script is to create enough redundancy so even if a single provider will fail you can still access your code using alternative hosting companies.

![how to](https://user-images.githubusercontent.com/6848691/77835310-cc29d180-714b-11ea-8a69-bd60ee6786cf.gif)


## How to use
### 1. Generate SSH key
```powershell
cd c:\Users\[USER_NAME]\.ssh\
ssh-keygen.exe
ssh-add.exe id_rsa
notepad.exe id_rsa.pub
```

In case you are using SSH agent delivered with Windows make sure that you enabled the **ssh-agent** service

To solve this problem
> Error connecting to agent: No such file or directory

follow instructions below
```powershell
Set-Service -Name ssh-agent -StartupType Manual
Start-Service ssh-agent
Get-Service ssh*
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