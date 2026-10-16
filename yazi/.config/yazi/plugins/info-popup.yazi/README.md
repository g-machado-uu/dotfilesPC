# info-popup.yazi

A lightweight [Yazi](https://github.com/sxyazi/yazi) plugin that displays a popup with detailed file or directory information when triggered by a keybinding.

It automatically inspects the currently hovered item and shows:

- **Directories:** Name, type, and total size.
- **PDF Files:** File size and total page count.
- **Image Files:** File size and resolution (width × height).
- **Other Files:** Name, file size, and standard properties.

---

## 🎨 Features

- **Asynchronous & Non-blocking:** External tools are executed asynchronously using Yazi's `Command` API, ensuring your UI never freezes or stutters.
- **Smart File Detection:** Automatically detects image extensions and PDF files to query appropriate metadata.
- **Graceful Fallbacks:** Checks for available system utilities (`pdfinfo` or `qpdf` for PDFs; `identify` for images) without crashing if one is missing.

---

## 📋 Prerequisites

To view extra metadata for images and PDFs, ensure the following CLI tools are installed on your system:

### 1. For PDF Page Counts

Install **Poppler** (provides `pdfinfo`) or **qpdf**:

- **Arch Linux:** `sudo pacman -S poppler`
- **Ubuntu/Debian:** `sudo apt install poppler-utils`
- **macOS:** `brew install poppler`
- **Fedora:** `sudo dnf install poppler-utils`

### 2. For Image Resolutions

Install **ImageMagick** (provides `identify`):

- **Arch Linux:** `sudo pacman -S imagemagick`
- **Ubuntu/Debian:** `sudo apt install imagemagick`
- **macOS:** `brew install imagemagick`
- **Fedora:** `sudo dnf install imagemagick`

---

## 📥 Installation

1. Clone or copy this repository into your Yazi plugins directory:

   **Linux / macOS:**

   ```bash
   mkdir -p ~/.config/yazi/plugins
   git clone [https://github.com/your-username/info-popup.yazi.git](https://github.com/your-username/info-popup.yazi.git) ~/.config/yazi/plugins/info-popup.yazi
   ```
