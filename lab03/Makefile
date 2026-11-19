CXXFLAGS ?= -O2 -Wall -Wextra -pedantic

.PHONY: all clean
all: dedup

dedup: dedup.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -std=c++17 $(LDFLAGS) -o $@ $< $(LDLIBS)

clean:
	rm -f dedup
