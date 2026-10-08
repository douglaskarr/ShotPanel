# ShotPanel

I got tired of screenshots clogging the Desktop and then having to go look for them. ShotPanel keeps those shots in one small panel, where I can open, copy, delete, and drag them out without hunting through a pile of files.

ShotPanel is a native macOS app. It does not take the screenshot. Cmd-Shift-3, Cmd-Shift-4, and Cmd-Shift-5 work as they do now. The panel only gathers the files macOS saves itself, the ones named Screenshot or Screen Shot. Other pictures stay where they are.

## Download

ShotPanel is free to use, distribute, and modify under the [MIT license](LICENSE).

[Download ShotPanel 1.1.0](https://github.com/douglaskarr/ShotPanel/releases/download/v1.1.0/ShotPanel-1.1.0.dmg) for macOS 14 or later.

Open the disk image and drag ShotPanel to Applications. The first time you open it, macOS may say it cannot verify the developer. Right-click ShotPanel, choose Open, then Open again. ShotPanel asks to read your screenshot folder before the panel opens, and asks whether to start at login. During screen sharing, the macOS question can appear on the Mac itself.

## What it does

The newest shot sits at the start of the list, large enough to read. Drag an edge or a corner and the panel keeps that size. When several shots fit, they sit side by side with space between them, and the next one shows as a faded sliver at the edge. A single shot scales down so the whole image stays inside the panel.

Right-click the panel and choose Horizontal or Vertical. Vertical stacks the same shots and swaps the panel's width and height. The info bar stays at the bottom. Each orientation remembers its own size.

Click a shot to select it. Copy and Delete appear on that image, and the bar shows its name, date and time, pixel size, and file size. Copy puts the image on the clipboard. Delete asks “Are you sure?” on the image, then moves that one file to the Trash. Delete all asks in the bar, then moves the whole group. Double-click, or right-click and choose Open, opens the file. Drag a shot into another app, a browser, or a folder. A drag that starts on a photo moves that one file.

Slide along the list with a finger on the top of the mouse, or press the trackpad and slide, and the row follows. Point at the panel and arrows appear on the ends that still have shots. The arrow keys move the row too. Drag the bar at the bottom to move the panel. The minus button, or Cmd-M, sends it to the Dock. While any screenshot is in the group, a ShotPanel folder also sits in the Dock just after Downloads, so the same files are one click from the Trash.

The menu bar icon can hide the panel, show it, turn Desktop capture on or off, open ShotPanel at login, or delete the group. On first launch, ShotPanel can keep new screenshots off the Desktop while it is open: shots already in the screenshot folder move into the panel, new ones skip the Desktop, and the floating thumbnail is turned off. Quitting, or turning that option off, restores the previous save location. The panel hides while a Space is in full screen.

## Use it

| Action | Result |
| --- | --- |
| Drag an edge or a corner | Resize. Shots scale to the new size, and the size stays |
| Drag the bottom bar | Move the panel |
| Slide along the list | Move through the shots. They enter and leave at the edges |
| Right-click, then Horizontal or Vertical | Turn the list sideways or upright. The panel swaps width and height |
| Click a shot | Select it. Copy and Delete appear on the image, and its name, time, pixel size, and file size appear in the bar |
| Copy | Copy that screenshot. The button says Copied |
| Delete | Ask “Are you sure?” on that image. Yes moves it to the Trash |
| Delete all | Ask “Are you sure?” in the bar. Yes moves the group to the Trash |
| Double-click, or right-click Open | Open the file |
| Drag a shot | Send that one file to another app, or move it into a folder |
| Minus, or Cmd-M | Minimize the panel to the Dock |
| Menu bar icon | Hide or show the panel, keep screenshots off the Desktop, delete the group, or quit |

## Credit

ShotPanel was inspired by [Tendedero](https://github.com/alejandrobujan/tendedero) by Alejandro Buján. Tendedero's clothesline was the idea I wanted: screenshots should gather in one place instead of covering the Desktop. This is a separate app, with its own name and icon. Tendedero's code is MIT. Its name and icon are not used here.

## Build

Requires Swift on macOS 14 or later.

```bash
scripts/build-app.sh
open build/ShotPanel.app
```

The local app is signed ad hoc. The first launch may need a right-click and Open, and macOS may ask before ShotPanel can read the Desktop.

`build/ShotPanel.app/Contents/MacOS/ShotPanel --preview /tmp/shotpanel-preview` writes snapshots of the widget.

## License

MIT. Copyright 2026 Douglas Karr.
