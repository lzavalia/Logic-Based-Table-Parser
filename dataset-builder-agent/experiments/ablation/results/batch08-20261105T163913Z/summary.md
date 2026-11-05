| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 4/10 | 4/10 | 4/10 |
| correct (complex) | 4/10 | 4/10 | 4/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 6 | 4 | 4 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 2 | 2 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 4/10 | 4/10 | 4/10 |
| cell accuracy, answered | 0.911 | 0.961 | 0.954 |
| cell accuracy, end to end | 0.911 | 0.769 | 0.764 |
| model calls | 10 | 10 | 10 |
| input tokens | 57,878 | 57,878 | 55,852 |
| output tokens | 6,488 | 6,091 | 6,827 |
| input tokens per table | 5,788 | 5,788 | 5,585 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC8359171/t0 | complex/subtables | wrong_accepted (0.79), 5,433 in | rejected, 5,433 in | rejected, 5,269 in |
| PMC4916417/t2 | complex/separator_rows | correct (1.00), 4,441 in | correct (1.00), 4,441 in | correct (1.00), 4,267 in |
| PMC4683911/t1 | complex/multi_level | correct (1.00), 7,099 in | correct (1.00), 7,099 in | correct (1.00), 6,831 in |
| PMC5387038/t3 | complex/subtables | wrong_accepted (0.87), 6,575 in | wrong_accepted (0.87), 6,575 in | wrong_accepted (0.87), 6,411 in |
| PMC9661877/t28 | complex/separator_rows | wrong_accepted (0.94), 11,459 in | wrong_accepted (0.94), 11,459 in | wrong_accepted (0.94), 11,285 in |
| PMC5496892/t2 | complex/multi_level | correct (1.00), 4,781 in | correct (1.00), 4,781 in | correct (1.00), 4,513 in |
| PMC12229061/t1 | complex/subtables | wrong_accepted (0.79), 4,811 in | rejected, 4,811 in | wrong_accepted (0.89), 4,633 in |
| PMC4310929/t1 | complex/separator_rows | wrong_accepted (0.94), 5,467 in | wrong_accepted (0.94), 5,467 in | wrong_accepted (0.94), 5,267 in |
| PMC11288899/t1 | complex/multi_level | correct (1.00), 3,445 in | correct (1.00), 3,445 in | correct (1.00), 3,177 in |
| PMC4468928/t10 | complex/subtables | wrong_accepted (0.79), 4,367 in | wrong_accepted (0.95), 4,367 in | rejected, 4,199 in |
