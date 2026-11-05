| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 7/10 | 7/10 | 9/10 |
| correct (complex) | 7/10 | 7/10 | 9/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 3 | 2 | 0 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 1 | 1 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 7/10 | 7/10 | 9/10 |
| cell accuracy, answered | 0.973 | 0.982 | 1.000 |
| cell accuracy, end to end | 0.973 | 0.884 | 0.900 |
| model calls | 10 | 10 | 10 |
| input tokens | 66,324 | 66,324 | 64,102 |
| output tokens | 5,700 | 6,322 | 7,256 |
| input tokens per table | 6,632 | 6,632 | 6,410 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC5754143/t7 | complex/subtables | correct (1.00), 5,469 in | correct (1.00), 5,469 in | correct (1.00), 5,201 in |
| PMC5496892/t1 | complex/separator_rows | correct (1.00), 4,149 in | correct (1.00), 4,149 in | correct (1.00), 3,971 in |
| PMC7018020/t6 | complex/multi_level | correct (1.00), 8,685 in | correct (1.00), 8,685 in | correct (1.00), 8,417 in |
| PMC8094449/t10 | complex/subtables | wrong_accepted (0.92), 5,075 in | wrong_accepted (0.92), 5,075 in | rejected, 4,907 in |
| PMC10575777/t0 | complex/separator_rows | correct (1.00), 11,919 in | correct (1.00), 11,919 in | correct (1.00), 11,745 in |
| PMC11596707/t1 | complex/multi_level | correct (1.00), 6,783 in | correct (1.00), 6,783 in | correct (1.00), 6,515 in |
| PMC4310929/t0 | complex/subtables | wrong_accepted (0.89), 5,593 in | rejected, 5,593 in | correct (1.00), 5,393 in |
| PMC4563231/t0 | complex/separator_rows | correct (1.00), 4,159 in | correct (1.00), 4,159 in | correct (1.00), 3,997 in |
| PMC5874310/t3 | complex/multi_level | correct (1.00), 5,581 in | correct (1.00), 5,581 in | correct (1.00), 5,313 in |
| PMC9314986/t0 | complex/subtables | wrong_accepted (0.91), 8,911 in | wrong_accepted (0.91), 8,911 in | correct (1.00), 8,643 in |
