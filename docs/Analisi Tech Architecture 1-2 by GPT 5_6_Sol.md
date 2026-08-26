Verdetto: la 1.2 è un miglioramento sostanziale, non cosmetico. Ora l’architettura è credibile e onesta sui propri limiti.

Passerei da **7/10 a circa 8,5/10 come direzione architetturale** e da **5/10 a 7,5/10 come specifica implementabile**. Approvazione immediata per la **Tappa 0**; approvazione del full build subordinata, correttamente, ai risultati degli spike.

Ho anche verificato che l’allegato e la copia in `docs/PRD.md` sono identici.

## Cosa è stato risolto bene

Quasi tutte le obiezioni principali sono state affrontate nel modo giusto:

- `DerivedCache` e `DurableState` sono finalmente distinti anche fisicamente.
- `FileOps` non finge più di essere transazionale: log di intenti, passi idempotenti e crash recovery sono il modello corretto.
- La portabilità dei giudizi è ora espressa mediante una matrice di casi supportati, best-effort e impossibili.
- L’hash non viene più promosso impropriamente a identità universale.
- FSEvents ora contempla volume, perdita della cronologia, raffiche continue e riconciliazione completa.
- XMP è trattato come un protocollo d’interoperabilità da provare, non come magia garantita dalla parola “standard”.
- Lo stato degli occhi è correttamente chiamato euristica dell’app.
- I risultati Vision/Core ML sono versionati semanticamente.
- Lo scheduler onnisciente è stato sostituito da code specializzate e una banda di ritenzione.
- Il percorso a tappe riduce davvero il rischio d’integrazione, pur mantenendo lo scope.

Soprattutto, il documento ora distingue correttamente fra **ricostruibile**, **recuperabile** e **best-effort**. È un salto di qualità importante.

## Cosa correggerei ancora

### 1. `DurableState` è separato, ma non ancora davvero “durevole”

Separare i due SQLite protegge dal pulsante “svuota cache”, ma non da:

- corruzione del database;
- migrazione fallita;
- disco pieno;
- cancellazione accidentale;
- crescita illimitata del journal.

Manca il contratto operativo di `DurableState`: modalità SQLite/WAL e livello di sincronizzazione, backup consistente, retention della cronologia, integrity check e recovery da corruzione.

Inoltre `DerivedCache` e `DurableState` condividono comunque informazioni, per esempio rating e stato di sincronizzazione. Quindi questa frase di ADR-003 è troppo forte:

> nessuna transazione che li attraversi — accettabile perché non condividono invarianti

Un’invariante esiste, ma deve essere monodirezionale: **DurableState/sidecar sono autorevoli; DerivedCache può restare indietro ed essere riallineata**. Definirei esplicitamente l’ordine:

1. scrittura del nuovo stato in `DurableState`;
2. tentativo sidecar;
3. aggiornamento opportunistico della cache;
4. riconciliazione delle righe sporche al riavvio.

### 2. Il recovery ha bisogno di un terzo esito

Il documento dice spesso che un lotto incompleto viene “ripreso o compensato”. Non sempre sarà possibile fare una delle due cose: il volume può essere smontato, il file modificato esternamente, lo spazio esaurito, il permesso revocato o il Cestino svuotato.

La macchina a stati dovrebbe prevedere almeno:

- `completed`;
- `compensated`;
- `partiallyRecovered`;
- `blockedNeedsUser`;
- eventualmente `abandonedByUser`.

Il contratto realistico non è “possiamo sempre concludere o riportare indietro”, ma:

> possiamo sempre riconoscere lo stato raggiunto, tentare una ripresa o compensazione e dichiarare esplicitamente ciò che richiede intervento umano.

Per lo stesso motivo FR-077 non dovrebbe dire che l’errore di un singolo file non interrompe mai il lotto. Un errore locale può essere saltato; un errore sistemico — volume scomparso, permessi revocati, disco pieno — deve sospenderlo.

### 3. Il budget usa necessariamente delle stime

La correzione allo scheduler è giusta, ma NFR-P10 dice:

> costi misurati, non stimati

Per ammettere un lavoro prima di eseguirlo, il sistema deve comunque stimarne il costo. La formulazione corretta sarebbe:

> stime conservative calibrate mediante misure reali, suddivise per tipo di lavoro, formato, classe di risoluzione e hardware, con margine di sicurezza e feedback dalla pressione di memoria.

Una media misurata “per tipo di lavoro” non protegge dall’immagine anomala che consuma cinque volte il normale.

### 4. Il tempo massimo di riconciliazione non può valere come completamento

Su un volume SMB bloccato, un disco smontato o un File Provider non disponibile non si può garantire che la riconciliazione termini entro un limite.

Garantirei invece che:

- il tentativo venga **avviato** entro il tempo massimo;
- l’I/O sia cancellabile e soggetto a timeout;
- l’interfaccia mostri `aggiornamento in corso`, `vista potenzialmente obsoleta` o `volume non disponibile`.

Inoltre FSEvents potrebbe non offrire lo stesso contratto su tutti i volumi. Il cancello n. 2 dovrebbe poter concludere che servono fallback diversi: FSEvents, riconciliazione periodica, refresh manuale o supporto limitato.

### 5. `NSFileCoordinator` non controlla tutte le applicazioni

Il coordinamento funziona bene con processi che partecipano al protocollo. Un’applicazione che scrive il sidecar senza coordinarsi può ancora entrare nella finestra fra controllo della versione e sostituzione.

ADR-013 dovrebbe quindi evitare di suggerire una protezione assoluta. Aggiungerei:

- controllo della versione dentro l’accessor coordinato;
- verifica dopo la sostituzione;
- conservazione temporanea della versione precedente;
- recovery esplicito se una scrittura concorrente non coordinata viene rilevata.

Il round-trip concorrente del cancello n. 3 deve includere deliberatamente anche un writer che ignora `NSFileCoordinator`.

## Due osservazioni minori

La frase “distribuzione a terzi fuori portata fino alla sandbox” resta inesatta: un `.dmg` notarizzato è già distribuzione a terzi. La sandbox è necessaria per il Mac App Store, non per distribuire direttamente l’app.

Inoltre `Access` è un buon confine di codice, ma non è un confine di sicurezza. L’app resta monoprocesso, non sandboxed e interpreta immagini potenzialmente corrotte. Registrerei almeno un ADR sul rischio accettato e sull’eventuale isolamento futuro di decodifica/analisi in un processo XPC.

## Conclusione

Questa versione la approverei come **architettura proposta da validare**. Non è più un documento che pretende di avere già risolto il filesystem: descrive correttamente quali decisioni sono provvisorie e come verificarle.

Le quattro correzioni davvero importanti prima di partire sono:

1. durabilità e autorità di `DurableState`;
2. stato `blocked/partial` nella recovery;
3. budget basato su stime conservative calibrate;
4. distinzione fra riconciliazione avviata e completata.

Fatte queste, il documento sarebbe abbastanza solido da smettere di revisionare l’architettura sulla carta e iniziare la Tappa 0.