#	 Copyright 2016 Carter Kindley.
#	 Authored by Carter Kindley.
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Initialize VB assembly for input dialogues
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null
# Initialize log file in same directory as script.
$logPath = '.\FSRM-screen-log.txt'
Echo "Initializing script..." > $logPath
#Check If FSRM Services Are Already Installed
$check = Get-WindowsFeature | Where-Object {$_.Name -eq "FS-Resource-Manager"}
If ($check.Installed -ne "True") {
        #Install/Enable SNMP Services
		Echo "Installing FSRM Role" >> $logPath
        Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools
}
$a = new-object -comobject wscript.shell 
# Ask user if global settings need configuration.
# If yes, will set SMTP server and addresses, add the file group, and add the screen template.
# Will also create the scheduled task to replace the file group daily.
$intAnswer = $a.popup("Do you want to set FSRM settings?", ` 
0,"FSRM Settings",4) 
If ($intAnswer -eq 6) { 
# Prompt for this environment's SMTP server
$smtpServer = [Microsoft.VisualBasic.Interaction]::InputBox("Enter SMTP server for this environment:", "Select SMTP Server", "")
# Prompt for admin email address
$adminEmail = [Microsoft.VisualBasic.Interaction]::InputBox("Enter the admin email for notification delivery:", "Admin Email", "")
# Prompt for user account name.
$fromEmail = [Microsoft.VisualBasic.Interaction]::InputBox("Enter the sending address:", "From Email", "")
Set-FsrmSetting -AdminEmailAddress $adminEmail -FromEmailAddress $fromEmail -SmtpServer $smtpServer | Out-File $logPath -Append
new-FsrmFileGroup -name "Anti-Ransomware File Groups" -IncludePattern @((Invoke-WebRequest -Uri "https://fsrm.experiant.ca/api/v1/combined").content | convertfrom-json | % {$_.filters}) | Out-File $logPath -Append
$Action = New-FsrmAction -Type Email -MailTo "[Admin Email]" -Subject "Ransomware file detected" -Body "User [Source Io Owner] attempted to save [Source File Path] to [File Screen Path] on [Server]. This appears to be a ransomware action."
New-FsrmFileScreenTemplate -Name "Ransomware Block" -IncludeGroup "Anti-Ransomware File Groups" -Notification $Action -Active | Out-File $logPath -Append
# Initialize parameters for scheduled task.
$task = New-ScheduledTaskAction -Execute 'Powershell.exe'`
		-Argument '-NoProfile -WindowStyle Hidden -command "& {Set-FsrmFileGroup -name \"Anti-Ransomware File Groups\" -IncludePattern @((Invoke-WebRequest -Uri \"https://fsrm.experiant.ca/api/v1/combined\").content | convertfrom-json | % {$_.filters}) } " '
$trigger = New-ScheduledTaskTrigger -Daily -At 1am
Register-ScheduledTask -Action $task -Trigger $trigger -TaskName "UpdateRWDefs" -Description "Daily update of Ransomware definitions"
		}
# Prompt for share path.
$sharePath = [Microsoft.VisualBasic.Interaction]::InputBox("Enter the share path to be protected. Do not set to the root of the system partition.", "Share Path", "")
# Create the file screen.
New-FsrmFileScreen -Description "Ransomware Block $sharePath" -Path $sharePath -Template "Ransomware Block" | Out-File $logPath -Append