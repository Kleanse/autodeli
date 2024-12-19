# Autodeli

Simple plugin for completing bracket delimiters automatically in Vim.

![demo](https://github.com/user-attachments/assets/f38b2587-5b1f-4e30-b682-95151eac838f)

## What is it?

Autodeli is a simple plugin for Vim that makes typing [bracket
delimiters](https://en.wikipedia.org/wiki/Delimiter#Bracket_delimiters) easier.
When typing the opening character of a delimiter pair, you will also insert its
closing character. For example, where `|` represents the cursor, entering `(`

    int foo|

yields

    int foo(|)

Deletion works similarly: Autodeli will delete the closing character (with some
stipulations) of a pair when its opening character is deleted.

For details, see the [help file](doc/autodeli.txt).

## Installation

Install with your package manager of choice or Vim's built-in support for
packages (see `:help packages`):

    mkdir -p ~/.vim/pack/autodeli/start
    cd ~/.vim/pack/autodeli/start
    git clone https://github.com/kleanse/autodeli.git
    vim -u NONE -c "helptags autodeli/doc" -c q

## Usage

Enter `:Autodeli` to see if Autodeli was installed successfully. You should get
a message indicating whether Autodeli is active.

To enable Autodeli, use `:Autodeli on`. Likewise, use `:Autodeli off` to
disable the plugin. Use `:Autodeli help` to see the arguments that the command
accepts and their descriptions.

For more information, see the "Using Autodeli" section in the [help
file](doc/autodeli.txt).

### Delimiters

Autodeli supports the following delimiter pairs:

| Delimiter | Name          |
| :-------: | ------------- |
|   \( \)   | Parentheses   |
|   \[ \]   | Brackets      |
|   \{ \}   | Braces        |
|    ' '    | Single quotes |
|    " "    | Double quotes |
