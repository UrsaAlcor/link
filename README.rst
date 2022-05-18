Link
====

Link is wrapped using a lua script so set ``-rpath`` when the software is linking against libraries inside our stack.
This enable us to module load packages with complex dependencies without module loading those.
The dependencies can be overriden by loading them explicitly.


* rpath is set if 
    
    * -L is detected to be within the stack and 
    * -l appears to select something that actually exists within the specified directory.
    
* I default to whitelisting selected directories for ld.lua's  -L -l special handling, like CUDA.

* rpath is not set if the path is inside the deny list (notably the CUDA "stubs" sub-directories)


.. note::

   ``-rpath`` is used to set ``DT_RUNPATH`` not ``DT_RPATH`` which is deprecated.


.. note::

   ``DT_RPATH`` is set by disabling the new behaviour with the argument flag ``--disable-new-dtags`` 
