| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 103/170 | 104/170 | 113/170 |
| correct (complex) | 101/165 | 102/165 | 111/165 |
| correct (simple) | 2/5 | 2/5 | 2/5 |
| wrong but accepted | 66 | 42 | 39 |
| invalid output | 1 | 0 | 0 |
| rejected (unparseable) | 0 | 24 | 18 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 103/170 | 104/170 | 113/170 |
| cell accuracy, answered | 0.948 | 0.973 | 0.975 |
| cell accuracy, end to end | 0.948 | 0.835 | 0.871 |
| model calls | 170 | 170 | 170 |
| input tokens | 1,097,466 | 1,097,466 | 1,061,772 |
| output tokens | 111,204 | 112,367 | 116,602 |
| input tokens per table | 6,456 | 6,456 | 6,246 |

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
| PMC12826758/t0 | complex/separator_rows | wrong_accepted (0.90), 4,421 in | correct (1.00), 4,421 in | correct (1.00), 4,327 in |
| PMC8132967/t2 | complex/multi_level | correct (1.00), 4,663 in | correct (1.00), 4,663 in | correct (1.00), 4,395 in |
| PMC12539739/t3 | complex/separator_rows | correct (1.00), 4,915 in | correct (1.00), 4,915 in | correct (1.00), 4,725 in |
| PMC12066955/t2 | complex/multi_level | correct (1.00), 3,661 in | correct (1.00), 3,661 in | correct (1.00), 3,393 in |
| PMC13525349/t5 | complex/separator_rows | correct (1.00), 7,957 in | correct (1.00), 7,957 in | correct (1.00), 7,827 in |
| PMC9661877/t21 | complex/multi_level | wrong_accepted (0.97), 4,385 in | wrong_accepted (0.97), 4,385 in | wrong_accepted (0.97), 4,117 in |
| PMC4483251/t0 | complex/separator_rows | wrong_accepted (0.81), 10,927 in | wrong_accepted (0.81), 10,927 in | wrong_accepted (0.81), 10,749 in |
| PMC12854148/t5 | complex/multi_level | correct (1.00), 4,535 in | correct (1.00), 4,535 in | correct (1.00), 4,267 in |
| PMC9822893/t4 | complex/separator_rows | correct (1.00), 6,037 in | correct (1.00), 6,037 in | correct (1.00), 5,891 in |
| PMC7018020/t7 | complex/multi_level | correct (1.00), 8,565 in | correct (1.00), 8,565 in | correct (1.00), 8,297 in |
| PMC11704328/t3 | complex/separator_rows | correct (1.00), 5,147 in | correct (1.00), 5,147 in | correct (1.00), 5,053 in |
| PMC6904686/t2 | complex/multi_level | correct (1.00), 3,823 in | correct (1.00), 3,823 in | correct (1.00), 3,555 in |
| PMC12487654/t1 | complex/separator_rows | correct (1.00), 9,741 in | correct (1.00), 9,741 in | correct (1.00), 9,631 in |
| PMC10152309/t1 | complex/multi_level | wrong_accepted (0.81), 8,601 in | correct (1.00), 8,601 in | correct (1.00), 8,333 in |
| PMC10470671/t2 | complex/separator_rows | wrong_accepted (0.95), 8,087 in | rejected, 8,087 in | correct (1.00), 8,009 in |
| PMC8987291/t3 | complex/multi_level | wrong_accepted (0.87), 4,849 in | rejected, 4,849 in | rejected, 4,581 in |
| PMC7911108/t0 | complex/separator_rows | wrong_accepted (0.92), 13,401 in | wrong_accepted (0.92), 13,401 in | wrong_accepted (0.92), 13,267 in |
| PMC4030731/t2 | complex/multi_level | correct (1.00), 10,097 in | rejected, 10,097 in | correct (1.00), 9,829 in |
| PMC10754813/t1 | complex/separator_rows | correct (1.00), 7,993 in | correct (1.00), 7,993 in | correct (1.00), 7,887 in |
| PMC11596707/t3 | complex/multi_level | correct (1.00), 4,385 in | correct (1.00), 4,385 in | correct (1.00), 4,117 in |
| PMC5815492/t17 | complex/separator_rows | wrong_accepted (0.87), 3,069 in | wrong_accepted (0.93), 3,069 in | wrong_accepted (0.93), 2,869 in |
| PMC12322749/t1 | complex/multi_level | correct (1.00), 11,035 in | rejected, 11,035 in | correct (1.00), 10,767 in |
| PMC12955956/t0 | complex/separator_rows | wrong_accepted (0.89), 5,737 in | wrong_accepted (0.89), 5,737 in | wrong_accepted (0.89), 5,563 in |
| PMC9661877/t14 | complex/multi_level | wrong_accepted (0.94), 9,603 in | wrong_accepted (0.94), 9,603 in | wrong_accepted (0.94), 9,335 in |
| PMC4916417/t0 | complex/separator_rows | correct (1.00), 6,101 in | correct (1.00), 6,101 in | correct (1.00), 5,991 in |
| PMC10882683/t0 | complex/multi_level | correct (1.00), 5,035 in | correct (1.00), 5,035 in | correct (1.00), 4,767 in |
| PMC6010922/t2 | complex/separator_rows | wrong_accepted (0.90), 7,359 in | wrong_accepted (0.90), 7,359 in | wrong_accepted (0.90), 7,213 in |
| PMC13500716/t1 | complex/multi_level | correct (1.00), 6,583 in | rejected, 6,583 in | correct (1.00), 6,315 in |
| PMC4317962/t0 | complex/separator_rows | correct (1.00), 7,453 in | correct (1.00), 7,453 in | correct (1.00), 7,435 in |
| PMC12863919/t2 | complex/multi_level | correct (1.00), 5,001 in | correct (1.00), 5,001 in | correct (1.00), 4,733 in |
| PMC12688946/t2 | complex/separator_rows | correct (1.00), 4,393 in | correct (1.00), 4,393 in | correct (1.00), 4,203 in |
| PMC9661877/t26 | complex/multi_level | wrong_accepted (0.95), 5,697 in | wrong_accepted (0.95), 5,697 in | wrong_accepted (0.95), 5,429 in |
| PMC4310929/t3 | complex/separator_rows | wrong_accepted (0.93), 5,043 in | wrong_accepted (0.93), 5,043 in | wrong_accepted (0.93), 4,843 in |
| PMC10981836/t1 | complex/multi_level | correct (1.00), 4,697 in | correct (1.00), 4,697 in | correct (1.00), 4,429 in |
| PMC9822893/t0 | complex/separator_rows | correct (1.00), 5,103 in | correct (1.00), 5,103 in | correct (1.00), 4,957 in |
| PMC6439288/t1 | complex/multi_level | correct (1.00), 5,185 in | correct (1.00), 5,185 in | correct (1.00), 4,917 in |
| PMC3939643/t0 | complex/separator_rows | correct (1.00), 6,595 in | correct (1.00), 6,595 in | correct (1.00), 6,569 in |
| PMC6010922/t3 | complex/multi_level | correct (1.00), 3,733 in | correct (1.00), 3,733 in | correct (1.00), 3,465 in |
| PMC12382306/t4 | complex/separator_rows | correct (1.00), 4,381 in | correct (1.00), 4,381 in | correct (1.00), 4,203 in |
| PMC3605494/t0 | complex/multi_level | correct (1.00), 5,317 in | correct (1.00), 5,317 in | correct (1.00), 5,049 in |
| PMC4310929/t6 | complex/separator_rows | wrong_accepted (0.93), 7,161 in | wrong_accepted (0.93), 7,161 in | wrong_accepted (0.93), 6,961 in |
| PMC13627762/t2 | complex/multi_level | wrong_accepted (0.89), 5,669 in | wrong_accepted (0.89), 5,669 in | wrong_accepted (0.89), 5,401 in |
| PMC11132289/t1 | complex/separator_rows | correct (1.00), 3,721 in | wrong_accepted (0.97), 3,721 in | correct (1.00), 3,527 in |
| PMC9661877/t22 | complex/multi_level | wrong_accepted (0.96), 5,417 in | wrong_accepted (0.96), 5,417 in | wrong_accepted (0.96), 5,149 in |
| PMC8407250/t2 | complex/separator_rows | wrong_accepted (0.92), 5,733 in | wrong_accepted (0.92), 5,733 in | wrong_accepted (0.92), 5,547 in |
| PMC8132967/t0 | complex/multi_level | correct (1.00), 4,027 in | correct (1.00), 4,027 in | correct (1.00), 3,759 in |
| PMC4802489/t0 | complex/separator_rows | correct (1.00), 6,893 in | correct (1.00), 6,893 in | correct (1.00), 6,703 in |
| PMC6843367/t4 | complex/multi_level | invalid_output (0.82), 3,903 in | rejected, 3,903 in | wrong_accepted (0.86), 3,635 in |
| PMC7780720/t0 | complex/separator_rows | wrong_accepted (0.88), 8,093 in | wrong_accepted (0.94), 8,093 in | rejected, 7,931 in |
| PMC5815492/t3 | complex/multi_level | wrong_accepted (0.35), 5,733 in | rejected, 5,733 in | rejected, 5,465 in |
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
| PMC5815492/t16 | complex/separator_rows | wrong_accepted (0.91), 3,103 in | wrong_accepted (0.91), 3,103 in | wrong_accepted (0.91), 2,903 in |
| PMC9661877/t31 | complex/multi_level | wrong_accepted (0.95), 6,087 in | wrong_accepted (0.95), 6,087 in | wrong_accepted (0.95), 5,819 in |
| PMC11253273/t0 | complex/separator_rows | wrong_accepted (0.84), 16,297 in | wrong_accepted (0.84), 16,297 in | wrong_accepted (0.84), 16,119 in |
| PMC3602089/t1 | complex/multi_level | correct (1.00), 4,421 in | correct (1.00), 4,421 in | correct (1.00), 4,153 in |
| PMC11972404/t2 | complex/separator_rows | correct (1.00), 4,693 in | correct (1.00), 4,693 in | correct (1.00), 4,547 in |
| PMC12863919/t1 | complex/multi_level | correct (1.00), 5,049 in | correct (1.00), 5,049 in | correct (1.00), 4,781 in |
| PMC11825198/t1 | complex/separator_rows | correct (1.00), 3,689 in | correct (1.00), 3,689 in | correct (1.00), 3,509 in |
| PMC11663277/t1 | complex/multi_level | correct (1.00), 4,683 in | correct (1.00), 4,683 in | correct (1.00), 4,415 in |
| PMC4916417/t3 | complex/separator_rows | correct (1.00), 5,011 in | correct (1.00), 5,011 in | correct (1.00), 4,833 in |
| PMC10981836/t2 | complex/multi_level | correct (1.00), 7,777 in | correct (1.00), 7,777 in | correct (1.00), 7,509 in |
