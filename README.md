# Bushscript

Bushscript is a Java program that launches a browser window directly from NetBeans.

## Prerequisites

Before starting, make sure you have:

* Java installed
* NetBeans IDE installed
* Basic knowledge of Java and NetBeans

## Installation

### Step 1: Create the Project

1. Open NetBeans.
2. Create a new Java project named `Bushscript`.
3. Open the project's `src` folder.
4. Copy the contents of [`Bushscript.java`](https://github.com/OpenBushate/bushscript/blob/main/script/Bushscript.java).
5. Paste the code into your project's main Java file.

Make sure the class and file are both named:

```text
Bushscript
```

### Step 2: Run Bushscript

Click **Run Project** in NetBeans.

The browser should open automatically. When you close the program, the browser process will also terminate.

## Optional: Create a Desktop Shortcut

You can create a Windows batch file to launch Bushscript without opening NetBeans.

1. Open Notepad.
2. Paste the following command:

```bat
@echo off
cd /d "C:\Users\USERNAME_HERE\Documents\NetBeansProjects\Bushscript"
java src\Bushscript.java
pause
```

3. Replace `USERNAME_HERE` with your Windows username.

For example:

```bat
@echo off
cd /d "C:\Users\abrown01\Documents\NetBeansProjects\Bushscript"
java src\Bushscript.java
pause
```

4. Select **File → Save As**.
5. Set **Save as type** to **All Files**.
6. Name the file something like:

```text
Bushscript.bat
```

You can now double-click the `.bat` file to launch Bushscript.

## Package Notice

If `Bushscript.java` contains a package declaration, such as:

```java
package bushscript;
```

the file will normally be located inside:

```text
src\bushscript\Bushscript.java
```

In that case, update the batch file command to use the correct file path:

```bat
java src\bushscript\Bushscript.java
```

## Source Code

The original source code is available here:

```text
https://github.com/OpenBushate/bushscript
```
