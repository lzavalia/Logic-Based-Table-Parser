| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 6/10 | 7/10 | 7/10 |
| correct (complex) | 6/10 | 7/10 | 7/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 4 | 2 | 3 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 1 | 0 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 6/10 | 7/10 | 7/10 |
| cell accuracy, answered | 0.947 | 0.972 | 0.978 |
| cell accuracy, end to end | 0.947 | 0.875 | 0.978 |
| model calls | 10 | 10 | 10 |
| input tokens | 71,200 | 71,200 | 68,998 |
| output tokens | 6,366 | 6,473 | 6,555 |
| input tokens per table | 7,120 | 7,120 | 6,900 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC11651604/t1 | complex/subtables | wrong_accepted (0.81), 9,107 in | wrong_accepted (0.81), 9,107 in | wrong_accepted (0.97), 8,907 in |
| PMC9035189/t0 | complex/separator_rows | correct (1.00), 6,831 in | correct (1.00), 6,831 in | correct (1.00), 6,641 in |
| PMC8427842/t1 | complex/multi_level | correct (1.00), 3,467 in | correct (1.00), 3,467 in | correct (1.00), 3,199 in |
| PMC13467166/t3 | complex/subtables | correct (1.00), 4,781 in | correct (1.00), 4,781 in | correct (1.00), 4,513 in |
| PMC7911108/t3 | complex/separator_rows | correct (1.00), 6,339 in | correct (1.00), 6,339 in | correct (1.00), 6,161 in |
| PMC12495617/t2 | complex/multi_level | correct (1.00), 6,149 in | correct (1.00), 6,149 in | correct (1.00), 5,881 in |
| PMC5387038/t8 | complex/subtables | wrong_accepted (0.87), 10,821 in | rejected, 10,821 in | wrong_accepted (0.87), 10,653 in |
| PMC12382306/t2 | complex/separator_rows | correct (1.00), 6,053 in | correct (1.00), 6,053 in | correct (1.00), 5,927 in |
| PMC9661877/t17 | complex/multi_level | wrong_accepted (0.93), 11,343 in | wrong_accepted (0.93), 11,343 in | wrong_accepted (0.93), 11,075 in |
| PMC8038080/t0 | complex/subtables | wrong_accepted (0.85), 6,309 in | correct (1.00), 6,309 in | correct (1.00), 6,041 in |
