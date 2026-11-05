| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 7/10 | 7/10 | 8/10 |
| correct (complex) | 7/10 | 7/10 | 8/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 3 | 2 | 1 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 1 | 1 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 7/10 | 7/10 | 8/10 |
| cell accuracy, answered | 0.977 | 0.981 | 0.985 |
| cell accuracy, end to end | 0.977 | 0.883 | 0.887 |
| model calls | 10 | 10 | 10 |
| input tokens | 59,178 | 59,178 | 57,064 |
| output tokens | 6,670 | 7,017 | 6,739 |
| input tokens per table | 5,918 | 5,918 | 5,706 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC7018020/t5 | complex/subtables | correct (1.00), 4,619 in | correct (1.00), 4,619 in | correct (1.00), 4,351 in |
| PMC7113237/t0 | complex/separator_rows | correct (1.00), 5,131 in | correct (1.00), 5,131 in | correct (1.00), 5,033 in |
| PMC8132967/t1 | complex/multi_level | correct (1.00), 6,483 in | correct (1.00), 6,483 in | correct (1.00), 6,215 in |
| PMC8099387/t1 | complex/subtables | wrong_accepted (0.96), 9,801 in | wrong_accepted (0.96), 9,801 in | rejected, 9,533 in |
| PMC8915277/t1 | complex/separator_rows | correct (1.00), 4,875 in | correct (1.00), 4,875 in | correct (1.00), 4,717 in |
| PMC11397705/t0 | complex/multi_level | correct (1.00), 3,911 in | correct (1.00), 3,911 in | correct (1.00), 3,643 in |
| PMC3465856/t0 | complex/subtables | wrong_accepted (0.95), 8,473 in | rejected, 8,473 in | correct (1.00), 8,297 in |
| PMC5496892/t3 | complex/separator_rows | correct (1.00), 4,261 in | correct (1.00), 4,261 in | correct (1.00), 4,083 in |
| PMC11991517/t2 | complex/multi_level | correct (1.00), 4,041 in | correct (1.00), 4,041 in | correct (1.00), 3,773 in |
| PMC5387038/t2 | complex/subtables | wrong_accepted (0.87), 7,583 in | wrong_accepted (0.87), 7,583 in | wrong_accepted (0.87), 7,419 in |
