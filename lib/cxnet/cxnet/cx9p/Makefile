# Generate *.py templates from the 9P files

all: messages.py

messages.py: messages.py.in fcall.h define-msg-classes.pl
	cat messages.py.in > messages.py
	echo >> messages.py
	echo >> messages.py
	cat fcall.h | ./define-msg-classes.pl >> messages.py

clean:
	rm -f messages.py
