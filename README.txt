s3eIOSiCloud extension for Marmalade
====================================

Info:
-----

This extension provides basic support for reading / writing and conflict resolution for a single file.
The interface is made as simple as possible and it doesn't even make distinction between regular reading from iCloud and iCloud conflict resolution - in both cases user simple gets the S3E_IOSICLOUD_CALLBACK_MERGE callback invoked and is supposed to merge with current game state / savegame.
The intented use assumes that the app stores game state locally anyway - whether iCloud is or isn't enabled. This is to make sure that changes / progress made in game is never lost.
More information on how to use the code can be found in HOWTO.txt

The extension is available for iOS only although simple Windows based simulation code has been implemented for testing / debugging purposes.

License:
--------

Everyone is free to use the code for both commercial and non-commercial purposes (but I don't guarantee that the code works).

Bugs / feedback:
----------------

If you found any bugs or issues please report via github at https://github.com/macieks/s3eIOSiCloud
Thanks!

Maciej Sawitus, 23.02.2012