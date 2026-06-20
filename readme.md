# ShrekStorageDrive
(working title.)

This is my new CC storage system. It is early in development, you're welcome to try it out, but expect things to change and it to be rough around the edges.

## Term Plugins (`tscreens`)
The terminal can load plugins from independant lua files, these plugins are executed with an environment of type `SSDTermPluginENV`. This contains the standard clientapi instance `_ENV.capi`, along with a library for interacting with the terminal `_ENV.tapi`. 