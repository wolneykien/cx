
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
