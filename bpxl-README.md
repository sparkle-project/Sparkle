# Black Pixel Modificaitons

##6fa3c561

Made changes to the AutoUpdate target to let Xcode manage signing on this target.  Without this setting, our custom Build Phase Script title "Resign Everything" was failing on with an error that "AutoUpdate was never signed so cannot be resigned".  This simple change solved the error for both the Kaleidoscope and Versions project.
