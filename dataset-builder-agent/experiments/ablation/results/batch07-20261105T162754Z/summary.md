| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 7/10 | 6/10 | 7/10 |
| correct (complex) | 7/10 | 6/10 | 7/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 3 | 2 | 2 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 2 | 1 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 7/10 | 6/10 | 7/10 |
| cell accuracy, answered | 0.967 | 0.968 | 0.975 |
| cell accuracy, end to end | 0.967 | 0.775 | 0.878 |
| model calls | 10 | 10 | 10 |
| input tokens | 63,492 | 63,492 | 61,582 |
| output tokens | 6,429 | 6,514 | 6,037 |
| input tokens per table | 6,349 | 6,349 | 6,158 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC5891175/t1 | complex/subtables | correct (1.00), 5,529 in | rejected, 5,529 in | correct (1.00), 5,355 in |
| PMC12382306/t1 | complex/separator_rows | correct (1.00), 3,781 in | correct (1.00), 3,781 in | correct (1.00), 3,603 in |
| PMC5874310/t1 | complex/multi_level | correct (1.00), 6,959 in | correct (1.00), 6,959 in | correct (1.00), 6,691 in |
| PMC8094449/t11 | complex/subtables | wrong_accepted (0.92), 5,393 in | rejected, 5,393 in | wrong_accepted (0.92), 5,225 in |
| PMC11704328/t0 | complex/separator_rows | correct (1.00), 8,289 in | correct (1.00), 8,289 in | correct (1.00), 8,163 in |
| PMC7559631/t0 | complex/multi_level | wrong_accepted (0.86), 4,283 in | wrong_accepted (0.86), 4,283 in | wrong_accepted (0.86), 4,015 in |
| PMC13467166/t2 | complex/subtables | wrong_accepted (0.89), 5,785 in | wrong_accepted (0.89), 5,785 in | rejected, 5,517 in |
| PMC13525349/t3 | complex/separator_rows | correct (1.00), 7,027 in | correct (1.00), 7,027 in | correct (1.00), 6,865 in |
| PMC12125436/t3 | complex/multi_level | correct (1.00), 5,945 in | correct (1.00), 5,945 in | correct (1.00), 5,677 in |
| PMC12688826/t2 | complex/subtables | correct (1.00), 10,501 in | correct (1.00), 10,501 in | correct (1.00), 10,471 in |
