# Cancello n°4 — Sintesi in linguaggio semplice

Questa è una sintesi divulgativa di due documenti tecnici:

- [`RESULT.md`](RESULT.md), l'esito completo del cancello n°4, con tutte le misure;
- [Lotti di operazioni su file recuperabili con esiti dichiarati](../../docs/wiki/decisions/recoverable-file-batches.md), la pagina Wiki con la regola di funzionamento che ne deriva.

Qui le spiegazioni sono semplificate e molti dettagli sono omessi. I conteggi esatti, la loro origine e i limiti della misura sono nei due documenti originali, che restano il riferimento.

## A cosa serviva il test

iMAGE Surfer lavorerà su molte foto in un colpo solo, in quelli che chiamiamo **lotti**: rinominarle, spostarle, copiarle, mandarle nel Cestino. Accanto a ogni foto c'è spesso un piccolo file gemello, il *sidecar* (`.xmp`), con le informazioni aggiunte alla foto, che deve viaggiare insieme a lei.

Il disco non permette di fare molte operazioni «tutte insieme o nessuna». Se l'app si interrompe a metà lotto, alcune foto sono già state toccate e altre no.

Il PRD, nella decisione di progetto ADR-007, prometteva questo:

- l'app annota che cosa sta per fare **prima** di farlo;
- dopo un'interruzione riconosce a che punto era;
- il lotto finisce sempre in uno di **cinque esiti** chiari per l'utente: completato, annullato (nei documenti «compensato»), recuperato in parte, bloccato in attesa dell'utente, abbandonato dall'utente.

Erano promesse scritte a tavolino. Il cancello n°4 serviva a verificarle prima di scrivere il codice dell'app.

Per farlo è stato costruito un piccolo programma di prova, da buttare dopo l'uso. Lavora su un piccolo disco di prova separato, mai sulle foto o sul Cestino dell'utente. Tutte le misure sono state fatte su un MacBook Pro M1 Pro con macOS 27.2.

La promessa poteva avere uno di due esiti:

- **confermata**: regge così com'è scritta;
- **emendata**: va riscritta con delle correzioni.

ADR-007 è risultato **emendato**: l'impianto regge, ma tre punti vanno corretti. Il PRD non è stato modificato. Il testo corretto da sostituire è pronto in `RESULT.md`, sezione *Esito su ADR-007*, sotto *Testo di sostituzione*.

## Come è stata fatta la prova

**Un lotto di prova.** Cinque foto, ciascuna con il suo sidecar, e cinque operazioni, una per tipo:

- rinominare una foto;
- spostarne una nella cartella `selezione`;
- spostarne una e rinominarla;
- copiarne una nella cartella `consegna`;
- mandarne una nel Cestino.

**61 momenti di interruzione.** Il programma chiude l'app di colpo, senza darle modo di salvare nulla, in ognuno di questi momenti:

- prima, durante e dopo ogni singolo passo del lotto;
- durante l'annullamento di un lotto già concluso;
- due casi in cui l'app viene chiusa una seconda volta proprio mentre sta rimettendo in ordine.

**La ripartenza.** Poi riapre l'app e le chiede di rimettere in ordine in una di due direzioni:

- **portare a termine** il lotto;
- **annullarlo**, riportando ogni foto al suo posto.

Alla fine confronta ogni affermazione dell'app con una fotografia esatta del disco.

**Gli imprevisti.** Fra l'interruzione e la ripartenza il programma può creare uno di otto problemi:

- disco scollegato;
- cartella resa non scrivibile;
- disco pieno;
- file sparito;
- file bloccato;
- file modificato da qualcun altro;
- posto di arrivo già occupato da un altro file;
- Cestino svuotato.

In tutto 146 scenari, ciascuno ripetuto 5 volte: 645 ripetizioni e circa 43 minuti di prove automatiche.

## I risultati

### 1. L'app capisce sempre a che punto era (regge)

- In nessuno dei 146 scenari l'app ha frainteso dove si trovassero le foto, e ogni scenario ha dato lo stesso risultato in tutte e 5 le ripetizioni.
- Da 60 dei 61 momenti di interruzione l'app porta a termine o annulla il lotto, come le si chiede. Dopo ogni completamento le foto sono esattamente dove dovevano finire.
- **Il disco ha l'ultima parola.** A volte l'app ha già spostato una foto ma viene chiusa prima di annotarlo. Il suo registro dice «non fatto», il disco dice «fatto». L'app se ne accorge, lo segnala e si fida del disco, che dice com'è davvero.
- **Foto e sidecar separati.** Se l'interruzione cade fra lo spostamento della foto e quello del suo gemello, i due restano divisi. L'app se ne accorge in tutti i 53 scenari in cui succede. Quando può li riunisce, altrimenti lo segnala.

### 2. Serve un sesto esito (da correggere)

L'unico momento da cui l'app non arriva a nessun esito è quello in cui viene chiusa mentre sta ancora scrivendo il piano del lotto.

Nessuna foto è stata toccata, e l'app lo riconosce. Ma nessuno dei cinque esiti descrive la situazione:

- il lotto non è completato;
- non c'è nulla da annullare;
- nessun errore aspetta l'utente;
- l'utente non ha abbandonato niente.

La proposta è un sesto esito: **«interrotto prima di agire»**. Vale anche per un caso che il PRD già prevede: l'app ricontrolla la situazione subito prima di agire e si ferma se qualcosa è cambiato.

### 3. «Annullato» non vuol dire «tutto come prima» (da correggere)

Quando l'app annulla un lotto, ogni foto e ogni sidecar torna al suo posto, intatto. Il disco però non torna identico a prima: in 57 annullamenti su 59 restano piccole tracce.

- **La data di modifica della cartella del lotto.** L'app vi aveva creato le cartelle `selezione` e `consegna`, e annullando le rimuove. La cartella torna com'era, ma la sua data di ultima modifica no.
- **Le copie annullate finiscono nel Cestino.** Il PRD vieta di cancellare direttamente i file, quindi annullare una copia significa mandarla nel Cestino.
- **Un file di servizio nel Cestino**, che macOS crea da sé.

Gli unici due annullamenti senza tracce sono quelli interrotti prima che l'app creasse qualsiasi cosa.

La promessa diventa quindi: «ogni operazione è stata annullata, e l'app ti dice che cosa resta». Non più: «il disco è identico a prima».

### 4. Alcuni problemi fermano tutto, altri solo un file (da correggere)

**Problemi che riguardano tutto il lotto: disco scollegato, cartella non scrivibile, disco pieno.** Continuare produrrebbe centinaia di errori identici, quindi l'app si ferma e aspetta l'utente. È l'esito «bloccato», raggiunto in 13 scenari, tutti di questo tipo. L'utente sceglie:

- **«riprova»**, dopo aver risolto il problema: il lotto si conclude in tutti i casi;
- **«abbandona»**: l'app non tocca più niente e dice dove si trova ogni foto.

Un problema di questo tipo blocca solo se l'app ne ha bisogno: se il lotto è già finito, una cartella non scrivibile non dà fastidio.

**Problemi su un solo file: file sparito, bloccato, modificato da altri, posto di arrivo occupato, Cestino svuotato.** L'app salta quel file e prosegue con gli altri. Il lotto si chiude «recuperato in parte», e l'app dice quale file ha saltato e perché. Succede in 17 scenari, nessuno dei quali finisce bloccato.

**La correzione.** Il PRD metteva il file modificato da altri e il Cestino svuotato fra i casi in cui l'app non può né completare né annullare. In realtà impediscono un solo file, non il lotto.

**Una sorpresa.** Il disco pieno non ferma solo le copie: anche una semplice rinomina può fallire. È stato visto in un solo scenario. Basta a dire che può succedere, non che succeda sempre.

## La regola di funzionamento che ne deriva

La pagina Wiki trasforma le misure in regole per l'app.

**Prima annota, poi agisce.** L'app scrive nel registro ogni passo prima di farlo, e ricontrolla la situazione subito prima di cominciare.

**Al riavvio guarda il disco.** Lo stato di ogni foto si ricava dal disco, non dal registro. Se i due non sono d'accordo, l'app lo dice e decide il disco.

**Le foto si riconoscono dal contenuto.** Ogni file si cerca con una sorta di impronta digitale del suo contenuto, non con il nome. Questo vale anche nel Cestino, dove macOS può cambiargli nome: è così che l'app ritrova una foto cestinata e la rimette al suo posto.

**Prima si capisce quanto è grave.** Davanti a un errore l'app si chiede, in quest'ordine:

1. il disco c'è?
2. si può scrivere?
3. c'è spazio?
4. solo alla fine, il problema riguarda il singolo file?

Non si decide mai solo dal messaggio d'errore del sistema. Per macOS, «disco scollegato» e «file sparito» danno lo stesso codice d'errore, ma il primo deve bloccare il lotto e il secondo no.

**Dopo un annullamento, si dichiara che cosa resta.** Le tracce della sezione 3 vanno mostrate all'utente. In un annullamento parziale va mostrato anche ogni file non riportato, con il percorso e il motivo.

**Sei esiti, tutti visibili.** Gli esiti fanno parte dell'interfaccia, non del funzionamento interno: «bloccato in attesa dell'utente» serve solo se l'utente lo sa.

## Avvertenze

- **Chiusura forzata, non blackout.** Le prove simulano l'app che si chiude di colpo, non il Mac che si spegne per mancanza di corrente o per un blocco del sistema. In quei casi potrebbe perdersi ciò che il sistema non aveva ancora scritto sul disco, e la misura non li copre.
- **Un solo disco locale.** Dischi esterni, cartelle sincronizzate e dischi di rete sono il tema del cancello n°2.
- **Un lotto piccolo.** Cinque foto e cinque operazioni, una per tipo. Lotti grandi e più operazioni sullo stesso file non sono misurati.
- **Il registro della prova non è quello dell'app.** La prova usa un semplice file di testo, non il sistema di salvataggio previsto dal PRD, che resta da verificare.
- **Il disco pieno è simulato male.** La procedura che riempie il disco di prova è inaffidabile: due parti della prova sono state rifatte, e il caso è coperto da soli 2 scenari. Va corretta prima di riusare il banco.
- **«Riprova» non è ricontrollato sul disco.** Per quella scelta ci si è fidati dell'esito dichiarato dall'app.
- **Il ricontrollo prima di agire non è nella misura principale.** Il caso in cui l'app si ferma perché la situazione è cambiata è provato dai test automatici del banco, non dai 146 scenari.
- **Una decisione rimandata.** Quando l'app salta un file per un problema, la foto e il suo sidecar possono restare separati, e succede in 8 scenari. L'app lo segnala sempre, ma chi costruirà l'app dovrà decidere se, in quel caso, fermare anche il gemello.

## In sintesi

L'app può essere interrotta in qualunque momento di un lotto senza perdere il filo. Al riavvio capisce sempre a che punto era, porta a termine o annulla il lavoro e, quando serve l'utente, glielo dice.

La promessa del PRD regge, con tre correzioni:

- aggiungere un sesto esito, «interrotto prima di agire»;
- «annullato» significa «ogni operazione annullata, con le tracce dichiarate», non «disco identico a prima»;
- un file modificato da altri o un Cestino svuotato fanno saltare solo quel file, non fermano il lotto.
