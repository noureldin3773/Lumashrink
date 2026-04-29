on run
  set bundlePath to POSIX path of (path to me)
  set libraryDir to POSIX path of (path to library folder from user domain)
  set runtimeDir to bundlePath & "Contents/Resources/runtime"
  set launcherPath to runtimeDir & "/desktop_launcher.py"
  set logsDir to libraryDir & "Logs"
  set logPath to logsDir & "/Image Compressor.log"
  do shell script "mkdir -p " & quoted form of logsDir & " && cd " & quoted form of runtimeDir & " && nohup /usr/bin/python3 " & quoted form of launcherPath & " >> " & quoted form of logPath & " 2>&1 < /dev/null &"
  delay 0.7
  try
    tell application "Python" to activate
  end try
  quit
end run
