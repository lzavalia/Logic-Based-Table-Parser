| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 10/15 | 10/15 | 9/15 |
| correct (complex) | 10/15 | 10/15 | 9/15 |
| correct (simple) | – | – | – |
| wrong but accepted | 5 | 3 | 3 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 2 | 3 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 10/15 | 10/15 | 9/15 |
| cell accuracy, answered | 0.956 | 0.981 | 0.972 |
| cell accuracy, end to end | 0.956 | 0.850 | 0.777 |
| model calls | 15 | 15 | 15 |
| input tokens | 94,649 | 94,649 | 91,591 |
| output tokens | 9,705 | 9,708 | 11,579 |
| input tokens per table | 6,310 | 6,310 | 6,106 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC8453916/t3 | complex/subtables | correct (1.00), 3,937 in | correct (1.00), 3,937 in | correct (1.00), 3,669 in |
| PMC13015447/t0 | complex/separator_rows | correct (1.00), 3,421 in | correct (1.00), 3,421 in | correct (1.00), 3,227 in |
| PMC12518418/t1 | complex/multi_level | correct (1.00), 4,703 in | correct (1.00), 4,703 in | correct (1.00), 4,435 in |
| PMC5387038/t7 | complex/subtables | wrong_accepted (0.88), 10,179 in | wrong_accepted (0.88), 10,179 in | wrong_accepted (0.88), 9,911 in |
| PMC8407250/t4 | complex/separator_rows | wrong_accepted (0.92), 5,629 in | wrong_accepted (0.92), 5,629 in | wrong_accepted (0.92), 5,443 in |
| PMC5829520/t1 | complex/multi_level | wrong_accepted (0.61), 9,673 in | rejected, 9,673 in | rejected, 9,405 in |
| PMC12688826/t1 | complex/subtables | correct (1.00), 8,399 in | correct (1.00), 8,399 in | correct (1.00), 8,337 in |
| PMC11489153/t0 | complex/separator_rows | wrong_accepted (0.98), 5,975 in | rejected, 5,975 in | rejected, 5,969 in |
| PMC12044418/t1 | complex/multi_level | correct (1.00), 5,207 in | correct (1.00), 5,207 in | correct (1.00), 4,939 in |
| PMC10470671/t0 | complex/subtables | correct (1.00), 6,921 in | correct (1.00), 6,921 in | correct (1.00), 6,763 in |
| PMC5815492/t2 | complex/separator_rows | wrong_accepted (0.95), 4,609 in | wrong_accepted (0.95), 4,609 in | rejected, 4,423 in |
| PMC9661877/t5 | complex/multi_level | correct (1.00), 4,451 in | correct (1.00), 4,451 in | correct (1.00), 4,183 in |
| PMC11651604/t2 | complex/subtables | correct (1.00), 7,511 in | correct (1.00), 7,511 in | wrong_accepted (0.86), 7,311 in |
| PMC11484257/t1 | complex/separator_rows | correct (1.00), 4,365 in | correct (1.00), 4,365 in | correct (1.00), 4,175 in |
| PMC6023111/t5 | complex/multi_level | correct (1.00), 9,669 in | correct (1.00), 9,669 in | correct (1.00), 9,401 in |
