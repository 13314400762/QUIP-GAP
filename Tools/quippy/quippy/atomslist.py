import sys, os, fnmatch, re, itertools
from quippy import Atoms, AtomsReaders, AtomsWriters
from farray import *

def find_files(filepat, top=None):
   if top is None:
      top = os.getcwd()
      
   for path, dirlist, filelist in os.walk(top):
      for name in fnmatch.filter(filelist, filepat):
         yield os.path.join(path, name)

def read_files(filenames, frame=None, *args, **kwargs):
   for item in filenames:
      try:
         filename, value = item
      except ValueError:
         filename = item
      if frame is None:
         a = Atoms(filename, *args, **kwargs)
      else:
         a = AtomsList(filename, lazy=False, *args, **kwargs)[frame]
      a.params['filename'] = filename
      yield a

def AtomsReader(source, format=None, *args, **kwargs):
   """Generator to read successive frames from source"""

   opened = False
   if format is None:
      if isinstance(source, str):
         opened = True
         if source in AtomsReaders:
            format = source
         else:
            base, ext = os.path.splitext(source)
            format = ext[1:]
      else:
         format = source.__class__

   if format in AtomsReaders:
      source = iter(AtomsReaders[format](source, *args, **kwargs))

   for at in source:
      yield at

   if opened and hasattr(source, 'close'):
      source.close()
   

def AtomsWriter(dest, format=None, *args, **kwargs):
   """Return a file-like object capable of writing Atoms in the specified format.
      If `format` is not given it is inferred from the file extension of `dest`."""
   if format is None:
      if isinstance(dest, str):
         if dest in AtomsWriters:
            format = dest
         else:
            base, ext = os.path.splitext(dest)
            format = ext[1:]
      else:
         format = dest.__class__

   if format in AtomsWriters:
      return AtomsWriters[format](dest, *args, **kwargs)
   else:
      raise ValueError("Don't know how to write Atoms to format %r" % format)


class AtomsList(object):
   """Class for dealing with sequences of Atoms objects"""

   def __init__(self, source, format=None, lazy=None, store=True, *args, **kwargs):

      if format is None:
         if isinstance(source, str):
            if source in AtomsReaders:
               format = source
            else:
               base, ext = os.path.splitext(source)
               format = ext[1:]
         else:
            format = source.__class__

      if format in AtomsReaders:
         if lazy is None: #and hasattr(AtomsReaders[format], 'lazy'):
            lazy = AtomsReaders[format].lazy
         self._source = AtomsReaders[format](source, *args, **kwargs)
         self._itersource = iter(self._source)
      else:
         if not hasattr(source, '__iter__'):
            self._source = [source]
            self._itersource = iter(self._source)
         else:
            self._source = source
            self._itersource = iter(self._source)
         
      self._randomaccess = hasattr(self._source, '__getitem__') and hasattr(self._source, '__len__')
      self._store = store

      if lazy is None: lazy = True
      if self._store:
         if lazy:
            if self._randomaccess:
   #            print 'len(self._source) = %d' % len(self._source)
               self._list = [ None for a in frange(len(self._source)) ]
            else:
               self._list = []
         else:
            self._list = list(self._source)
      else:
         self._list = None

   def __repr__(self):
      return '%s(source=%r)' % (self.__class__.__name__, self._source)

   def __str__(self):
      return '%s(%r)' % (self.__class__.__name__, self._list)

   def __len__(self):
      if self._store:
         return len(self._list)
      else:
         if self._randomaccess:
            return len(self._source)
         else:
            raise ValueError('This AtomsList has no defined length')

   def __delitem__(self, frame):
      if not self._store: raise ValueError('cannot delete items from AtomsList where self._store is False')
      if frame == 0: raise ValueError('invalid index 0 -- AtomsList indices are one-based')
      if frame > 0: frame -= 1
      a = self._list[frame]
      self._list[frame] = None
      del a

   def iteratoms(self):
      if self._store:
         for frame in frange(len(self._list)):
            yield self[frame]
         if not self._randomaccess:
            for at in self._itersource:
               self._list.append(at)
               yield at
         if hasattr(self._source, 'close'):
            self._source.close()
         self._randomaccess = True
      else:
         # Create a new iterator every time
         for at in iter(self._source):
            yield at

   def __iter__(self):
      return self.iteratoms()

   def __reversed__(self):
      if not self._store: raise ValueError('cannot reverse AtomsList where self._store is False')
      if not self._randomaccess:
         raise ValueError('Cannot reverse AtomsList with generator source. Call loadall() then try again')
      for frame in reversed(frange(len(self._list))):
         yield self[frame]

   def __getslice__(self, first, last):
      return self.__getitem__(slice(first,last,None))

   def __getitem__(self, frame):
      if isinstance(frame, int):

         if frame == 0: raise ValueError('invalid index 0 -- AtomsList indices are one-based')
         if frame > 0: frame -= 1
         if frame < 0: frame = frame + len(self)

         if self._store:
            if not self._randomaccess and frame >= len(self._list):
               self._list.extend(list(itertools.islice(self._itersource, frame-len(self._list)+1)))
            if self._list[frame] is None:
               if isinstance(self._source, AtomsList):
                  self._list[frame] = self._source[frame+1]
               else:
                  self._list[frame] = self._source[frame]
            return self._list[frame]
         else:
            if not self._randomaccess:
               raise IndexError('cannot random access AtomsList where store and randomaccess are both False')
            else:
               return self._source[frame]

      elif isinstance(frame, slice):

         if frame.start == 0: raise ValueError('invalid slice index 0 -- AtomsList indices are one-based')
         if frame.start is not None and frame.start > 0:  frame = slice(frame.start - 1, frame.stop, frame.step)

         if self._store:
            if not self._randomaccess and frame.stop >= len(self._list):
               self._list.extend(list(itertools.islice(self._itersource, frame.stop != sys.maxint and frame.stop-len(self._list)+1 or None)))
            allatoms = range(len(self._list))
            subatoms = [ allatoms[i] for i in range(*frame.indices(len(allatoms))) ]
            res = []
            for f in subatoms:
               if self._list[f] is None:
                  if isinstance(self._source, AtomsList):
                     self._list[f] = self._source[f+1]
                  else:
                     self._list[f] = self._source[f]
               res.append(self._list[f])
            return AtomsList(res, lazy=False)
         else:
            if not self._randomaccess:
               raise IndexError('cannot random access AtomsList where store and randomaccess are both False')
            else:
               return [ self._source[i] for i in range(*frame.indices(len(self._source))) ]

      else:
         raise TypeError('frame should be either an integer or a slice')

   def __setslice__(self, i, j, value):
      if not self._store: raise ValueError('cannot set slice when self._store is False')
      if i == 0: raise ValueError('invalid index 0 -- AtomsList indices are one-based')
      if i > 0: i -= 1
      self._list[i:j] = value

   def __setitem__(self, i, value):
      if not self._store: raise ValueError('cannot set item when self._store is False')
      if i == 0: raise ValueError('invalid index 0 -- AtomsList indices are one-based')
      if i > 0: i -= 1
      self._list[i] = value

   def loadall(self, progress=False, progress_width=80, update_interval=None, show_value=True):
      if not self._store: raise ValueError('cannot load all items when self._store is False')
      if progress:
         if self._randomaccess:
            from progbar import ProgressBar
            pb = ProgressBar(0,len(self),progress_width,showValue=show_value)
            update_interval = update_interval or max(1, len(self)/progress_width)
         else:
            update_interval = update_interval or 100
      
      for i, a in fenumerate(self.iteratoms()):
         if progress and i % update_interval == 0:
            if self._randomaccess:
               pb(i)
            else:
               print i

   def show(self, property=None, frame=1, arrows=None, *arrowargs, **arrowkwargs):
      try:
         import atomeye
         atomeye.show(self, property, frame, arrows=arrows, *arrowargs, **arrowkwargs)
      except ImportError:
         raise RuntimeError('AtomEye not available')

   def write(self, dest, format=None, properties=None, progress=False, progress_width=80, update_interval=None,
             show_value=True, *args, **kwargs):
      opened = False
      if format is None:
         if isinstance(dest, str):
            opened = True
            if dest in AtomsWriters:
               format = dest
            else:
               base, ext = os.path.splitext(dest)
               format = ext[1:]
         else:
            format = dest.__class__
      
      if progress:
         if self._randomaccess:
            from progbar import ProgressBar
            pb = ProgressBar(0,len(self),progress_width,showValue=show_value)
            update_interval = update_interval or max(1, len(self)/progress_width)
         else:
            update_interval = update_interval or 100

      if format in AtomsWriters:
         dest = AtomsWriters[format](dest, *args, **kwargs)

      if not hasattr(dest, 'write'):
         raise ValueError("Don't know how to write to destination \"%s\" in format \"%s\"" % (dest, format))

      res = []
      for i, a in fenumerate(self.iteratoms()):
         if properties is not None:
            try:
               res.append(dest.write(a, properties=properties))
            except TypeError:
               raise ValueError('AtomsList.write destination does not support specifying properties')
         else:
            res.append(dest.write(a))
         if progress and i % update_interval == 0:
            if self._randomaccess:
               pb(i)
            else:
               print i

      if opened:
         dest.close()

      # Special case for writing to a string
      if format == 'string':
         return res[-1]
      else:
         if res is not None and not all(el is None for el in res):
            return res

   def __getattr__(self, name):

      try:
         return self._source.__getattr__(name)
      except AttributeError:

         numeric_types = [int, float ]
         array_types = [ FortranArray, numpy.ndarray ]
         numeric_dtype_kinds = [ 'i', 'f' ]

         seq = [ getattr(at, name) for at in self ]
         if seq == []: return seq

         s = seq[0]
         if type(s) in numeric_types:
            return farray(seq)
         elif type(s) in array_types and s.dtype.kind in numeric_dtype_kinds:
            if len(s.shape) == 2:
               return farray(numpy.dstack(seq))
            else:
               return farray(seq)
         else:
            return seq

# Decorator to add a new reader

def atoms_reader(source, lazy=True):
   def decorate(func):
      from quippy import AtomsReaders
      func.lazy = lazy
      if not source in AtomsReaders:
         AtomsReaders[source] = func
      return func
   return decorate
