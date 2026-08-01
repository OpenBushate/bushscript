# Bushscript

## How to Run

### Prerequisites

Before starting, make sure you have:

* NetBeans IDE
* Java installed
* Basic Java knowledge

## Step 1: Create the NetBeans Project

Create a new NetBeans project named:

```text
Bushscript
```

Copy the Java file from:

```text
https://github.com/OpenBushate/bushscript/blob/main/script/Bushscript.java
```

Paste the file into your NetBeans project.

Run the program through NetBeans. The browser should open automatically.

## Optional: Create a Desktop Shortcut

You can create a Windows batch file to launch the program without opening NetBeans.

1. Open Notepad.
2. Paste the following command:

```bat
java C:\Users\[USERNAME_HERE]\Documents\NetBeansProjects\Bushscript\src\Bushscript.java
```

3. Replace `[USERNAME_HERE]` with your Windows username or student email string.

For example:

```bat
java C:\Users\abrown01\Documents\NetBeansProjects\Bushscript\src\Bushscript.java
```

4. Save the file with a `.bat` extension, such as:

```text
Bushscript.bat
```

5. Set **Save as type** to **All Files**.

Double-click the `.bat` file to launch the browser. The program will terminate when the browser is closed.

## Package Folder

If the Java file is inside a package folder, include that folder in the path.

For example, if the file is located at:

```text
C:\Users\abrown01\Documents\NetBeansProjects\Bushscript\src\bushscript\Bushscript.java
```

use:

```bat
java C:\Users\abrown01\Documents\NetBeansProjects\Bushscript\src\bushscript\Bushscript.java
```
