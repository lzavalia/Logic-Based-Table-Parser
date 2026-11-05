| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 7/10 | 8/10 | 7/10 |
| correct (complex) | 7/10 | 8/10 | 7/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 3 | 1 | 2 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 1 | 1 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 7/10 | 8/10 | 7/10 |
| cell accuracy, answered | 0.956 | 0.993 | 0.981 |
| cell accuracy, end to end | 0.956 | 0.894 | 0.883 |
| model calls | 10 | 10 | 10 |
| input tokens | 58,046 | 58,046 | 55,904 |
| output tokens | 6,872 | 7,184 | 7,509 |
| input tokens per table | 5,805 | 5,805 | 5,590 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC8094449/t0 | complex/separator_rows | wrong_accepted (0.85), 5,777 in | correct (1.00), 5,777 in | rejected, 5,591 in |
| PMC9661877/t23 | complex/multi_level | wrong_accepted (0.94), 8,231 in | wrong_accepted (0.94), 8,231 in | wrong_accepted (0.94), 7,963 in |
| PMC5829520/t0 | complex/separator_rows | correct (1.00), 5,525 in | correct (1.00), 5,525 in | correct (1.00), 5,335 in |
| PMC11704328/t5 | complex/multi_level | correct (1.00), 4,327 in | correct (1.00), 4,327 in | correct (1.00), 4,059 in |
| PMC12973358/t1 | complex/separator_rows | correct (1.00), 5,481 in | correct (1.00), 5,481 in | correct (1.00), 5,407 in |
| PMC12495617/t4 | complex/multi_level | correct (1.00), 9,209 in | correct (1.00), 9,209 in | correct (1.00), 8,941 in |
| PMC12382306/t0 | complex/separator_rows | correct (1.00), 4,775 in | correct (1.00), 4,775 in | correct (1.00), 4,601 in |
| PMC6843367/t1 | complex/multi_level | wrong_accepted (0.77), 5,557 in | rejected, 5,557 in | wrong_accepted (0.89), 5,289 in |
| PMC13308667/t0 | complex/separator_rows | correct (1.00), 4,177 in | correct (1.00), 4,177 in | correct (1.00), 3,999 in |
| PMC7154833/t2 | complex/multi_level | correct (1.00), 4,987 in | correct (1.00), 4,987 in | correct (1.00), 4,719 in |
