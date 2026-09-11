# 输出动态库名称
OUTPUT = libtest.dylib
# 源码文件
SRC = main.m
# 编译器
CC = clang
# 编译参数：生成动态库，ObjC，链接Foundation框架
CFLAGS = -shared -fPIC -ObjC
LDFLAGS = -framework Foundation

all: $(OUTPUT)

$(OUTPUT): $(SRC)
	$(CC) $(CFLAGS) $(SRC) -o $(OUTPUT) $(LDFLAGS)

clean:
	rm -f $(OUTPUT)
