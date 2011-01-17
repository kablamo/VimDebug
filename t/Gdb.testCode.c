#include <stdio.h>

void foo();


void foo() {
   int foo = 0;
   int c   = 2 + foo;
}

int main() {
   int a = 1;
   int b = 2;
   int c = a + b;

   foo();

   char* monkey  = "i want bananas";
   char* gorilla = "i want bananas";
   printf("i want bananas\n");
}

