{
  "version": "0.2.0",
  "configurations": [
    {
      "request": "launch",
      "program": "${workspaceFolder}/target/debug-{{DEBUG_TARGET}}-launch",
      "cwd": "${workspaceFolder}",
      "name": "Forge: Debug",
      "type": "lldb",
      "preLaunchTask": "Forge: Debug build"
    }
  ]
}
