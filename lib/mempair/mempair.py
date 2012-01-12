# coding: utf-8

"""
The module for parsing a memory block constructing a list of pair
objects. Each pair consists of a static head of predetermined length
and stricture called a *car* and some tail, called a *cdr*, the length
and structure of which are known only in runtime. The cdr, if it is
defined, is always a pair itself.

1. Parsing in general
=====================

A memory block is always parsed consequently, from the start to the
end. The first *n* bytes of the block are accessd as the static head
of the first pair *p* via ``p.car()`` method.  The reset of the block
is supposed to be the next pair which can be potentially get via
``p.cdr()`` method. The length of that second pair is not defined save
for its static head, i.e. ``p.cdr().car()``: to define its class
(and therefore the structure) the ``p.car().cdarclass()`` method is
consulted. With the use of ``cdarclass()`` method the structure of the
next pair is determined in runtime on the base of values in the static
head of the previous pair. In particular case there could be no next
pair. In that case, the ``cdarclass()`` method should return
``type(None)``.

2. Parsing arrays
=================

In some cases, a car should not be responsible for the rest of the
block. That is a natural case for an element of an array: it may know
nothing of the next element because the array's head is responsible
for all of its elements. To implement that concept the «responsibility
handover» mechanism can be unilized. If an object is not responsible
for the class of the next pair's car the ``cdarclass()`` method simply
should not be defined. In that case the system tries same method in
the parent object with calculated index value as an argument. If it
isn't defined in the parent, the parent's parent object is tried, if
exists, and so on. The parent pointer and the index value are
related objects: the parent of a pair is the pair that defines class
of its car in a course of the described procedure while the index
value is incremented for each defined pair starting with 0.

3. Exceptions
=============

* If the length of the static head of a pair (car) exceeds the length
  of the memory block being parsed an ``OverflowError`` is raised.

* If the current set of values in the car object doesn't define a
  proper state and the class of the next pair's car can not be
  determined the ``TypeError`` or ``ValueError`` should be raised
  in the ``cdarclass()`` method.

* If the index value passed to the ``cdarclass()`` method exceeds
  some limit then the ``IndexError`` should be raised. In that case,
  as when no ``cdarclass()`` method is defined for a car object at all,
  the call is transferred to the parent object.
"""

from ctypes import c_ubyte, pointer, POINTER, cast, sizeof, byref

# Memory pairs

class mempair (object):
	"""
	A memory pair.
	"""

	def __init__ (self, carclass, data, parent = None, index = 0):
		"""
		Sets up the pair object.

		The ``carclass`` argument defines the class of the car
		object and should be ``ctypes``-compatible. The
		``data`` argument defines the memory block being
		parsed. The other arguments are optional and reserved
		for module internal use.
		"""
		if sizeof(data) >= sizeof(carclass):
			self.parent = parent
			self.index = index
			self.carclass = carclass
			self.data = data
			self.carobj = cast(data, POINTER(carclass)).contents
		else:
			raise OverflowError("The length of memory block (%d) is less than the length of the static head (%d)." % (sizeof(data), sizeof(carclass)))
	
	def car (self):
		"""
		Returns the static head of this pair.
		"""
		return self.carobj

	def buf (self):
		"""
		Returns the (address, length) tuple of the pair occupied
		memory buffer.
		"""
		(addr, size) = self.carbuf()
		cdr = self.cdr()
		if cdr:
			(cdraddr, cdrsize) = cdr.buf()
			size += cdrsize
		return (addr, size)

	def databuf (self):
		"""
		Returns the (address, length) tuple of the pair
		available memory buffer.
		"""
		return (byref(self.data), sizeof(self.data))

	def carbuf (self):
		"""
		Returns (address, length) tuple of the pair static head bufer.
		"""
		return (byref(self.data), sizeof(self.carclass))

	def cdr (self):
		"""
		Returns the pair that forms the tail of this pair.
		"""
		cdarclass = self.cdarclass()
		if cdarclass is not type(None):
			index = 0
			parent = self
		else:
			parent = self.parent
			index = self.index + 1

			while parent != None:
				try:
					cdarclass = parent.cdarclass (index)
					if cdarclass is not type(None):
						break
				except IndexError:
					pass
				index = parent.index  + 1
				parent = parent.parent
		
		if cdarclass != type(None):
			cdrbuf = cast(cast(self.data, POINTER(c_ubyte * 1))[sizeof(self.carclass)], POINTER(c_ubyte * (sizeof(self.data) - sizeof(self.carclass)))).contents
			return type(self)(cdarclass, cdrbuf, parent, index)
		else:
			return None

	def cdarclass (self, key = 0):
		try:
			if isinstance (key, int) or isinstance (key, long):
				pos = 0
				for (fname, ftype, fcount) in self.car().cdrmap():
					if pos < key:
						pos = pos + fcount
					else:
						return ftype
				raise IndexError ("Index out of bounds: %s" % key)
			else:
				for (fname, ftype, fcount) in self.car().cdrmap():
					if key == fname:
						return ftype
		except AttributeError:
			try:
				if key:
					return self.car().cdarclass (key)
				else:
					return self.car().cdarclass()
			except (AttributeError, TypeError):
				pass
		return type(None)

	def __getattr__ (self, name):
		try:
			return object.__getattribute__ (self, name)
		except AttributeError:
			try:
				return getattr (self.car(), name)
			except AttributeError:
				head = self.cdr()
				try:
					ftype = self.cdarclass (name)
					if ftype is not type(None):
						for (fname, ftype, fcount) in self.car().cdrmap():
							if name == fname:
								return head
							else:
								head = head.__skip (fcount)
				except AttributeError:
					pass
				while head:
					try:
						return object.__getattribute__ (head.car(), name)
					except AttributeError:
						head = head.cdr()
				raise AttributeError("No attribute '%s'" % name)

	def __setattr__ (self, name, value):
		try:
			carobj = object.__getattribute__ (self, "carobj")
		except AttributeError:
			object.__setattr__ (self, name, value)
			return
		try:
			object.__getattribute__ (carobj, name)
			object.__setattr__ (carobj, name, value)
		except AttributeError:
			cdr = self.cdr()
			while cdr:
				try:
					object.__getattribute__ (cdr.car(), name)
					object.__setattr__ (cdr.car(), name, value)
					return
				except AttributeError:
					cdr = cdr.cdr()
			object.__setattr__ (self, name, value)

	def __skip (self, count):
		if not count:
			return self
		cdarclass = self.cdarclass()
		if cdarclass is type(None):
			# Good, a static length element
			tail = cast(cast(self.data, POINTER(c_ubyte * 1))[sizeof(self.carclass) * count], POINTER(c_ubyte * (sizeof(self.data) - sizeof(self.carclass) * count))).contents
			return type(self)(self.carclass, tail, self.parent, self.index + count)
		else:
			# A variable length element — walk the list :/
			cdr = self
			for i in range (count):
				cdr = cdr.cdr()
			return cdr

	def __gethead (self):
		head = self.parent.cdr()
		pos = 0
		for (fname, ftype, fcount) in self.parent.car().cdrmap():
			if (pos + fcount) <= self.index:
				pos = pos + fcount
				head = head.__skip (fcount)
			else:
				break
		return head

	def __getitem__ (self, index):
		return self.__gethead().__skip (index)
