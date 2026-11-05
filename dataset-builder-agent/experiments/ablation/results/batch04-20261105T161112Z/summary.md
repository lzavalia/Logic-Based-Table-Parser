| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 6/10 | 7/10 | 8/10 |
| correct (complex) | 6/10 | 7/10 | 8/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 4 | 1 | 0 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 2 | 2 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 6/10 | 7/10 | 8/10 |
| cell accuracy, answered | 0.965 | 0.977 | 1.000 |
| cell accuracy, end to end | 0.965 | 0.782 | 0.800 |
| model calls | 10 | 10 | 10 |
| input tokens | 61,168 | 61,168 | 59,182 |
| output tokens | 6,864 | 6,559 | 8,195 |
| input tokens per table | 6,117 | 6,117 | 5,918 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC13384529/t1 | complex/subtables | wrong_accepted (0.89), 4,709 in | correct (1.00), 4,709 in | correct (1.00), 4,441 in |
| PMC12487654/t2 | complex/separator_rows | correct (1.00), 5,557 in | correct (1.00), 5,557 in | correct (1.00), 5,459 in |
| PMC4802489/t5 | complex/multi_level | correct (1.00), 7,081 in | correct (1.00), 7,081 in | correct (1.00), 6,813 in |
| PMC5720689/t0 | complex/subtables | correct (1.00), 7,557 in | correct (1.00), 7,557 in | correct (1.00), 7,289 in |
| PMC11489153/t1 | complex/separator_rows | wrong_accepted (0.98), 7,471 in | rejected, 7,471 in | rejected, 7,465 in |
| PMC4476672/t1 | complex/multi_level | correct (1.00), 3,967 in | correct (1.00), 3,967 in | correct (1.00), 3,699 in |
| PMC4468928/t9 | complex/subtables | wrong_accepted (0.83), 4,217 in | rejected, 4,217 in | rejected, 4,049 in |
| PMC11651604/t0 | complex/separator_rows | wrong_accepted (0.95), 7,925 in | wrong_accepted (0.82), 7,925 in | correct (1.00), 7,725 in |
| PMC12357927/t2 | complex/multi_level | correct (1.00), 6,119 in | correct (1.00), 6,119 in | correct (1.00), 5,851 in |
| PMC11077913/t2 | complex/subtables | correct (1.00), 6,565 in | correct (1.00), 6,565 in | correct (1.00), 6,391 in |
