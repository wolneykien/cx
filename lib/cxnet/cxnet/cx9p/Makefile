# Generate *.py templates from the 9P files

all: messages.py.out

messages.py.out: messages.py fcall.h define-msg-classes.pl man9/*.9p
	cat messages.py > messages.py.out
	echo >> messages.py.out
	echo >> messages.py.out
	cat fcall.h | ./define-msg-classes.pl >> messages.py.out

clean:
	rm -f messages.py.out
