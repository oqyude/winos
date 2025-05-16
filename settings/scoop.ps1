irm get.scoop.sh -outfile 'install.ps1'
%Temp%\install.ps1 -RunAsAdmin
iex "& {$(irm get.scoop.sh)} -RunAsAdmin"