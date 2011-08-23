"""
The module for parsing a memory block constructing a list of pair
objects. Each pair consists of a static head of predetermined length
and stricture called a *car* and some tail, called a *cdr*, the length
and structure of which are known only in runtime. The cdr, if it is
defined, is always a pair itself.

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
"""

from ctypes import c_ubyte, pointer, POINTER, cast, sizeof

# Memory pairs

class mempair (object):
	"""
	A memory pair
	"""

	def __init__ (self, carclass, data, parent = None, index = 0):
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
		Returns the (address, length) tuple of the pair memory buffer.
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
		try:
			cdarclass = self.car().cdarclass()
			index = 0
			parent = self
		except AttributeError:
			parent = self.parent
			index = self.index + 1
			cdarclass = type(None)

			while parent != None:
				try:
					cdarclass = parent.car().cdarclass(index)
					break
				except (AttributeError, TypeError, ValueError, IndexError):
					index = parent.index  + 1
					parent = parent.parent
		
		if cdarclass != type(None):
			cdrbuf = cast(cast(self.data, POINTER(c_ubyte * 1))[sizeof(self.carclass)], POINTER(c_ubyte * (sizeof(self.data) - sizeof(self.carclass)))).contents
			return type(self)(cdarclass, cdrbuf, parent, index)
		else:
			return None
