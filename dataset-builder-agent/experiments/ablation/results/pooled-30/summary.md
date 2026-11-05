| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 16/30 | 17/30 | 18/30 |
| correct (complex) | 14/25 | 15/25 | 16/25 |
| correct (simple) | 2/5 | 2/5 | 2/5 |
| wrong but accepted | 14 | 8 | 8 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 5 | 4 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 16/30 | 17/30 | 18/30 |
| cell accuracy, answered | 0.927 | 0.960 | 0.958 |
| cell accuracy, end to end | 0.927 | 0.800 | 0.830 |
| model calls | 30 | 30 | 30 |
| input tokens | 229,264 | 229,264 | 222,740 |
| output tokens | 18,462 | 18,734 | 19,701 |
| input tokens per table | 7,642 | 7,642 | 7,425 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC12914422/t0 | complex/subtables | correct (1.00), 9,887 in | correct (1.00), 9,887 in | correct (1.00), 9,619 in |
| PMC12688826/t3 | complex/separator_rows | correct (1.00), 4,437 in | correct (1.00), 4,437 in | correct (1.00), 4,247 in |
| PMC7555252/t0 | complex/multi_level | wrong_accepted (0.42), 11,731 in | rejected, 11,731 in | rejected, 11,463 in |
| PMC12434915/t0 | complex/subtables | wrong_accepted (0.98), 8,267 in | rejected, 8,267 in | correct (1.00), 8,111 in |
| PMC9822893/t6 | complex/separator_rows | correct (1.00), 5,145 in | correct (1.00), 5,145 in | correct (1.00), 4,999 in |
| PMC12632427/t0 | simple/simple | wrong_accepted (0.87), 3,243 in | wrong_accepted (0.87), 3,243 in | wrong_accepted (0.87), 2,975 in |
| PMC9656733/t1 | simple/simple | wrong_accepted (0.85), 4,211 in | wrong_accepted (0.85), 4,211 in | wrong_accepted (0.85), 3,943 in |
| PMC13190168/t5 | simple/simple | correct (1.00), 11,285 in | correct (1.00), 11,285 in | correct (1.00), 11,017 in |
| PMC1361785/t0 | simple/simple | correct (1.00), 4,171 in | correct (1.00), 4,171 in | correct (1.00), 3,903 in |
| PMC10199865/t2 | simple/simple | wrong_accepted (0.84), 40,201 in | wrong_accepted (0.84), 40,201 in | wrong_accepted (0.84), 39,933 in |
| PMC13096635/t0 | complex/multi_level | wrong_accepted (0.88), 8,139 in | rejected, 8,139 in | correct (1.00), 7,871 in |
| PMC11859888/t1 | complex/multi_level | wrong_accepted (0.82), 4,027 in | wrong_accepted (0.82), 4,027 in | wrong_accepted (0.82), 3,759 in |
| PMC12854148/t0 | complex/multi_level | correct (1.00), 4,703 in | correct (1.00), 4,703 in | correct (1.00), 4,435 in |
| PMC5387038/t5 | complex/subtables | wrong_accepted (0.87), 6,091 in | wrong_accepted (0.87), 6,091 in | wrong_accepted (0.87), 5,923 in |
| PMC10694873/t3 | complex/separator_rows | wrong_accepted (0.94), 9,077 in | correct (1.00), 9,077 in | correct (1.00), 8,951 in |
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
