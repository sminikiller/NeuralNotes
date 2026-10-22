# Patch 0.17.2/build 33 — retta con sbavatura iniziale

Il riconoscimento dopo una pressione ferma di circa 650 ms ora ammette un breve gancio all’inizio. Il margine è misurato sulla lunghezza del tratto, non sul numero di campioni: massimo 24 punti pagina e comunque non oltre il 12% della distanza fra estremi. Il resto deve essere una linea quasi retta; lo scostamento iniziale ammesso è limitato a 12 punti. Non viene aumentata la tolleranza alle pieghe centrali o finali.

La posizione iniziale viene proiettata sulla direzione del tratto principale, preservandone la posizione lungo la linea. Anteprima e inchiostro PencilKit salvato usano gli stessi estremi; resta l’aggancio agli angoli già previsto. Annulla e formato dei quaderni sono invariati. Conservata la barra inferiore compatta della 0.17.1.

Quattro nuovi test Core: gancio in cinque direzioni e proiezione dell’inizio; campionamento rado/denso e punti fermi; rifiuto di ganci grandi, pieghe a metà/fine, angoli e scarabocchi; tratti corti o non finiti. Eseguiti con successo. La suite completa verifica anche frecce, cerchi e rettangoli preesistenti. Controlli di struttura, grammatica/parsing e integrità del pacchetto non equivalgono a compilazione SDK Apple o prova fisica con Pencil.

La parte AI prosegue separatamente dalla patch, così il pacchetto della sola correzione rimane disponibile. Non contiene un servizio AI remoto attivato.

Verifica completa: **189 XCTest Core, 187 passati e due skip Darwin preesistenti, zero fallimenti; 98 FSRS passati**. Grafo 412 oggetti / 260 Swift / 326 metodi XCTest presenti. Grammatica e parsing Swift 5 riusciti; nessuna compilazione SDK o esecuzione iPad dichiarata. Backend invariato, non rieseguito.
