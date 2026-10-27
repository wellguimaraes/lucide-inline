# Lucide Inline

Menu bar app for macOS 14+ that works like the system emoji picker, but for [Lucide](https://lucide.dev) icons.

1. Press **⌃⌘L** anywhere. The picker opens at the text cursor. If no text field has focus, it opens in the center of the focused window.
2. Type to search by icon name or tag. Use the arrow keys to move through the grid.
3. Paste the selected icon:
   - **Enter**: icon name (`house`)
   - **⌘Enter**: SVG code (`<svg …>`)
   - **⌘⇧Enter**: SVG file (`house.svg`), for Finder, Slack, Mail, Keynote and other apps that take files

   Clicking an icon works the same way, with the same modifier keys. **Esc** closes the picker.

All four shortcuts can be changed in the menu bar icon → **Settings…**.

## Build

```sh
./scripts/build.sh            # creates build/Lucide Inline.app
./scripts/build.sh --install  # also copies it to /Applications and launches it
```

On first launch, allow **Lucide Inline** in System Settings → Privacy & Security → Accessibility.
The app needs this to find the text cursor and to send ⌘V. Without it, the picker opens in the
center of the screen and the text is only copied to the clipboard.

## Icon updates

The app checks npm for a new `lucide-static` release once a day and installs it on its own.
To check right away, open the menu bar icon and choose **Check for Icon Updates**.
Downloaded icons are saved in `~/Library/Application Support/Lucide Inline/icons.json`.
The app uses that file or its built-in copy, whichever has the newer version.

To update the built-in copy in the source tree:

```sh
node scripts/fetch-icons.mjs          # latest lucide-static
node scripts/fetch-icons.mjs 1.62.0   # specific version
```

## Credits

Icons are from [Lucide](https://lucide.dev) and are covered by the ISC license in [`Resources/LUCIDE-LICENSE`](Resources/LUCIDE-LICENSE).
