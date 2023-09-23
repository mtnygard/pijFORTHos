## Documentation

* Explain the name in the readme file.
* Create a vocab.md file with details of every word.
* As a starting point we need to be able to get the help strings out of the program.


## Syntax questions

* We need a single word string that stands out from other strings, essentially the Forty version of Clojure's :symbol.
* Alternatives:
  * Literally use :symbol. Advantage is code clarity: `123 :count set` just looks right. Disadvantage: Will it create confusion with the : defintions?
  * Use 'symbol. Advantage is that it suggests strings. Disadvantage is I like 'foo to mean the address of the word.
  * Use `symbol. Advantage is that it's a quote and it's not used. Disadvantage is confusion with shell meaning.
  * Use #symbol. Also makes sense in code clarity, unused char. Disadvantage: Confusion with decimal numbers?

* We need an easy way to create a word that contains a string, sized properly. Something like

  "hello world" :greetings new-string

* REPL in Forth
  * Goal: Get as much of the repl into forth as possible
  * Something like: 
```
  : repl 
    while 1 
    do 
      read-word
      eval-word 
      error-status
      0 !=
      if
        error-message s. cr
        reset
      endif
    ;
```
  * Ideally `read-word` would use a buffer allocated in Forth memory, but maybe not at first.
  * How do we actually handle err status?

