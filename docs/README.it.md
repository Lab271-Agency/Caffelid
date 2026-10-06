# Caffelid

**Tieni il Mac sveglio a coperchio chiuso, lasciando spegnere lo schermo.**

Una piccola app nativa per la barra dei menu: una tazzina, un interruttore e due
limiti configurabili per batteria e temperatura. Gratuita e open source con
[licenza MIT](../LICENSE).

**Apple Silicon · macOS 13+ · Italiano e inglese · Firmata e notarizzata da Apple**

[English](../README.md) · [Risoluzione dei problemi](TROUBLESHOOTING.md)

## Installazione

1. Scarica [**Caffelid.dmg**](https://github.com/Lab271-Agency/Caffelid/releases/latest/download/Caffelid.dmg) dalla [release più recente](https://github.com/Lab271-Agency/Caffelid/releases/latest).
2. Apri il DMG e trascina **Caffelid** in **Applicazioni**.
3. Apri l’app. Clicca la tazzina nella barra dei menu e attiva l’interruttore.
4. Alla prima attivazione, segui il messaggio per consentire Caffelid in
   **Impostazioni di Sistema → Generali → Elementi login ed estensioni → Consenti
   in background**. I nomi possono variare con la versione di macOS.
   Approva la richiesta amministratore direttamente sul Mac.

Il servizio di supporto è incluso: basta un download, senza installer separati.
Le attivazioni successive usano il servizio approvato senza chiedere nuovamente
la password. Non servono Xcode o un account Apple Developer per usare l’app.
Lascia Caffelid in Applicazioni.

## Il menu

| Controllo | Funzione |
| --- | --- |
| **Abilitato / Disabilitato** | Attiva o interrompe il blocco dello stop. La tazzina è piena quando è attivo. |
| **Limite batteria** | Ripristina lo stop alla percentuale scelta o sotto, a coperchio chiuso e senza alimentazione esterna. |
| **Limite temperatura** | Ripristina lo stop dopo 10 secondi consecutivi alla temperatura scelta o sopra, a coperchio chiuso. |
| **Avvia al login** | Apre Caffelid quando accedi. A ogni apertura l’app parte **disabilitata**. |
| **Esci** | Ripristina lo stop e chiude l’app. |

I limiti e la preferenza di avvio vengono salvati. Se un limite abilitato è già
raggiunto, l’app impedisce l’attivazione. Non si riattiva automaticamente quando
la batteria o la temperatura tornano entro i limiti. Segue la lingua del sistema;
per le lingue non disponibili usa l’inglese. Non compare nel Dock.

### Limiti predefiniti

- **Batteria: 10%.** Puoi scegliere Disattivato oppure da **5% a 70%**, a passi
  di 5%. Il limite non si applica quando il Mac è alimentato esternamente.
- **Temperatura: 95 °C.** Puoi scegliere da **75 °C a 100 °C**, a passi di 5 °C,
  e una posizione aggiuntiva Disattivato. La temperatura deve restare alla soglia
  o sopra per 10 secondi consecutivi. Se aumenta, il conteggio prosegue; se
  scende sotto la soglia, si azzera.

La temperatura mostrata è il valore più alto disponibile dei sensori CPU/GPU,
non quella della scocca. Una lettura non disponibile per un limite abilitato
impedisce l’attivazione. Se manca per 10 secondi mentre l’app è abilitata con il
coperchio chiuso, viene ripristinato lo stop.

## Schermo, alimentazione e privacy

Caffelid non modifica i timer dello schermo, la luminosità o l’opzione
**«Impedisci lo stop automatico quando lo schermo è spento»** relativa
all’alimentazione esterna. Disattivando l’app o uscendo, lo stop torna disponibile.
Il servizio lo ripristina anche se perde la connessione con l’app o viene riavviato.

A coperchio chiuso richiede lo spegnimento dello schermo. Se è collegato un
monitor esterno, lascia la gestione degli schermi a macOS, perché il comando
spegnerebbe tutti i monitor. Il blocco dello stop resta attivo.

L’app non effettua richieste di rete, non include analytics e non salva password.
Il permesso per il supporto in background è separato dall’avvio al login.

## Compatibilità

Il download della V1 contiene binari **arm64 per Mac Apple Silicon**. La versione
minima prevista è macOS 13; questo download non supporta i Mac Intel.
Le prove di sviluppo e fisiche sono state svolte su un MacBook Pro M1 Pro;
un ulteriore MacBook Pro M1 è stato usato per le prove sul campo. L’utente ha
confermato il funzionamento della build finale, ma non sono verificati tutti i
modelli e tutte le versioni di macOS. I sensori possono variare tra dispositivi.
I dettagli delle verifiche sono in [TESTING.md](TESTING.md).

## Aggiornamento e rimozione

Per aggiornare: apri il coperchio, disabilita Caffelid e scegli Esci, poi sostituisci
l’app in Applicazioni con quella del nuovo DMG. Le preferenze restano salvate.

Per rimuoverla: apri il coperchio, disabilita l’app, spegni Avvia al login e scegli
Esci. Disabilita il permesso in background nelle Impostazioni di Sistema, poi
sposta l’app nel Cestino. macOS può conservare una voce storica dopo la rimozione.

Per segnalare un problema, includi versione dell’app, modello del Mac, versione
e build esatte di macOS e passaggi per riprodurlo. Per segnalazioni di sicurezza
segui [SECURITY.md](../SECURITY.md).
