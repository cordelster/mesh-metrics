# Some better practices negotiating SSH crypto and keys for older Cisco devices.
With the ever increasing threat environment and ssh being locked down to FIPs only cyphers and keys, it may be needed to enable "weaker" ( as in not compromised though considered to be in the treat environment) cyphers for specific devices which don't support the stronger requirements for what ever reason.

For the purpose of the nxos_apass script, just either copy/create the config file into your working directory, use the full path, or link to the file in the working directory. I leave it to you to pick your poison that works best for you.



## Create SSH user config in your home directory

We create an initial config that reads a directory so we can organize configs to a specific task which makes removing them later easy to track:
#### vi ~/.ssh/ssh_config_bad
```
Include ~/.ssh/ssh_bad_conf.d/*
```
Create the config directory:
```
mkdir -p ~/.ssh/ssh_bad_conf.d
```
Now copy your default config from /etc/ssh/ssh_config.d folders and append the necessary cyphers and keys into the config. You can add regex hosts/ips if you want to get more granular as to what’s allowed (not covered here).
Quick and easy, this below config includes the in date  FIPs cyphers, as well as what is required for Cisco starting with strongest cyphers first without the need to copy and append anything ( already  done the work):

#### vi ~/.ssh/ssh_bad_conf.d/fips_cisco_ssh_config
```
Host *
Ciphers aes128-gcm@openssh.com,aes256-ctr
HostbasedAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com,ssh-rsa
KexAlgorithms ecdh-sha2-nistp256,ecdh-sha2-nistp384,diffie-hellman-group14-sha1
MACs hmac-sha2-256,hmac-sha1
PubkeyAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
CASignatureAlgorithms ecdsa-sha2-nistp256
ServerAliveCountMax 0
ServerAliveInterval 900
```
The above config will work with most Cisco devices not older than 10 years.

For anything using weaker or compromised cyphers, you should create a config that is directed specifically at the device or IP range. For example our ancient console server, create a separate config file that targets the server host only:

#### vi ~/.ssh/ssh_bad_conf.d/consolesvr_config
```
Host 10.16.167.200
    KexAlgorithms +diffie-hellman-group-exchange-sha1
    HostKeyAlgorithms +ssh-dss
ServerAliveCountMax 0
ServerAliveInterval 900
```

## Create the alias if you want to (can not be called in the script)
You may desire to create an alias if you find yourself dealing with a large number of devices on a consistent basis.
In MacOS, we have to modify or create (if it don't exist) a .zshrc file (makes the change persistent across reboots). Add the alias into this file:
#### vi ~/.zshrc
```
alias badssh='ssh -F ~/.ssh/ssh_config_bad'
```

## using the alias

Now any time you need to ssh into a older cisco device, you can just run badssh. Running ssh by itself will still hold the current integrity and security, while you have a quick way to access the older devices and always aware when you are doing so.
```
badssh admin@10.16.167.244
```
