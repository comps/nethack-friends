.PHONY: all clean

all: cp437 fake_uid.so

clean:
	rm -f cp437 fake_uid.so

cp437: cp437.c
	$(CC) -Wall -O2 -o $@ $< -lutil

fake_uid.so: fake_uid.c
	$(CC) -Wall -O2 -fPIC -shared -o $@ $<

