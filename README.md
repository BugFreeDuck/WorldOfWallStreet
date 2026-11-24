# World of Wall Street

<img src="logo.png" alt="drawing" width="300"/>

A World of Warcraft addon for tracking materials bought as investments and how their value changes, in the style of a stock portfolio.

This is the first scaffold. Loading the addon prints `Hello, World!` in chat.

## Layout

```
WorldOfWallStreet.toc   addon manifest
WorldOfWallStreet.lua   code run when the addon loads
```

The folder name and the `.toc` file name must match.

## Install

Copy or symlink this folder into the retail AddOns directory:

```
World of Warcraft\_retail_\Interface\AddOns\WorldOfWallStreet
```

Enable **World of Wall Street** on the character select screen, log in, and look for `Hello, World!` in the chat window.

The manifest targets interface `120105` (Midnight retail). If the addon list marks it out of date, check the client with `/dump select(4, GetBuildInfo())` and set `## Interface` in `WorldOfWallStreet.toc` to that number.
