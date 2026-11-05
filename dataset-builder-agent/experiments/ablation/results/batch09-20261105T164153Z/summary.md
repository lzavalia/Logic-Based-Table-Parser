| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 6/10 | 6/10 | 5/10 |
| correct (complex) | 6/10 | 6/10 | 5/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 4 | 2 | 2 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 2 | 3 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 6/10 | 6/10 | 5/10 |
| cell accuracy, answered | 0.933 | 0.982 | 0.979 |
| cell accuracy, end to end | 0.933 | 0.785 | 0.685 |
| model calls | 10 | 10 | 10 |
| input tokens | 60,446 | 60,446 | 58,380 |
| output tokens | 7,609 | 7,004 | 7,532 |
| input tokens per table | 6,045 | 6,045 | 5,838 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC12597348/t2 | complex/subtables | correct (1.00), 6,259 in | correct (1.00), 6,259 in | correct (1.00), 6,141 in |
| PMC13525349/t6 | complex/separator_rows | correct (1.00), 8,109 in | correct (1.00), 8,109 in | correct (1.00), 7,943 in |
| PMC7154833/t6 | complex/multi_level | correct (1.00), 4,967 in | correct (1.00), 4,967 in | correct (1.00), 4,699 in |
| PMC12955956/t1 | complex/subtables | correct (1.00), 5,433 in | correct (1.00), 5,433 in | correct (1.00), 5,259 in |
| PMC7113237/t2 | complex/separator_rows | correct (1.00), 5,527 in | correct (1.00), 5,527 in | rejected, 5,433 in |
| PMC7018020/t1 | complex/multi_level | correct (1.00), 4,327 in | correct (1.00), 4,327 in | correct (1.00), 4,059 in |
| PMC13467166/t1 | complex/subtables | wrong_accepted (0.75), 6,351 in | rejected, 6,351 in | rejected, 6,083 in |
| PMC9661877/t18 | complex/separator_rows | wrong_accepted (0.94), 9,935 in | wrong_accepted (0.94), 9,935 in | wrong_accepted (0.94), 9,761 in |
| PMC11224729/t0 | complex/multi_level | wrong_accepted (0.92), 6,127 in | wrong_accepted (0.92), 6,127 in | wrong_accepted (0.92), 5,859 in |
| PMC8094449/t6 | complex/subtables | wrong_accepted (0.72), 3,411 in | rejected, 3,411 in | rejected, 3,143 in |
