# Consensus Reactor

Consensus Reactor defines a reactor for the consensus service. When a peer p is added on the consensus reactor, it 
starts to manage peer state for the peer p, and starts the following three routines for the peer p: 
    - Gossip Data Routine
    - Gossip Votes Routine
    - QueryMaj23Routine.
    
TODO: Add round state and peer known state data structures!    
    
## Gossip Data Routine

It is used to send the following messages to the peer: `BlockPartMessage`, `ProposalMessage` and 
`ProposalPOLMessage` on the `DataChannel`. The gossip data routine is based on the local round state (denoted rs) 
and the known round state of the peer (denotes prs) that are being continuously updated during the course of this routine.
The routine repeats forever the logic shown below:

```
1a) if rs.ProposalBlockPartsHeader == prs.ProposalBlockPartsHeader and the peer does not have all the proposal parts then
        Part = pick a random proposal block part the peer does not have 
        Send BlockPartMessage(Height, Round, Part) to the peer on the DataChannel 
        if send returns true, record that the peer knows the corresponding block Part
	    Continue  

TODO: We should also probably cover the case where rs.ProposalBlockPartsHeader != prs.ProposalBlockPartsHeader.  
For example, rs.Height == prs.Height and rs.Round > prs.Round. What is the right
thing to do in this case? Should we send parts to our peer from the previous round when we know that we have moved to 
the higher round? Consider also the case when rs.Height < prs.Height. Although we are lagging behind, we might be still 
receiving messages from the higher consensus instances from other peers that are helping me catchup so I should forward
these messages immediatelly to my peer. Similar reasoning applies when rs.Height == prs.Height and rs.Round < prs.Round.
 
1b) if (0 < prs.Height) and (prs.Height < rs.Height) then
        help peer catch up using gossipDataForCatchup function
        Continue

1c) if (rs.Height != prs.Height) or (rs.Round != prs.Round) then 
        Sleep PeerGossipSleepDuration
        Continue
TODO: Maybe remove this rule and define preciselly what is the scenario when we can't help our peer (if there is such
scenario and when we should sleep!   

//  at this point rs.Height == prs.Height and rs.Round == prs.Round
1d) if (rs.Proposal != nil and !prs.Proposal) then 
        Send ProposalMessage(rs.Proposal) to the peer
        if send returns true, record that the peer knows Proposal
	    if 0 <= rs.Proposal.POLRound then
	    polRound = rs.Proposal.POLRound 
        prevotesBitArray = rs.Votes.Prevotes(polRound).BitArray() 
        Send ProposalPOLMessage(rs.Height, polRound, prevotesBitArray)
        Continue  
TODO: We should probably forward Proposal and ProposalPOLMessages even when we are not at the same height and round
as our peer, for example if we are lagging behind. Otherwise we might be blocking those messages about reaching our peer
in a timely fashion which is critical for consensus termination.  

2)  Sleep PeerGossipSleepDuration 
TODO: Probably we should remove this rule as we can almost always do something useful for our peers. Would it make sense
to be more message driven at this level, i.e., upon receiving message to decide based on peer state if we should throw 
message or keep it and forward it.
```

## Gossip Votes Routine

It is used to send the following message: `VoteMessage` over VoteChannel.

The gossip votes routine is based on the local round state (denoted rs) and the known round state of the peer
(denotes prs). The routine repeats forever the logic shown below:

```
1a) if rs.Height == prs.Height then
        if prs.Step == RoundStepNewHeight then    
            vote = random vote from rs.LastCommit the peer does not have  
            Send VoteMessage(vote) to the peer 
            if send returns true, continue
  
        if prs.Step <= RoundStepPrevote and prs.Round != -1 and prs.Round <= rs.Round then                 
            Prevotes = rs.Votes.Prevotes(prs.Round)
            vote = random vote from Prevotes the peer does not have  
            Send VoteMessage(vote) to the peer 
            if send returns true, continue

        if prs.Step <= RoundStepPrecommit and prs.Round != -1 and prs.Round <= rs.Round then   
     	    Precommits = rs.Votes.Precommits(prs.Round) 
            vote = random vote from Precommits the peer does not have  
            Send VoteMessage(vote) to the peer 
            if send returns true, continue
	
        if prs.ProposalPOLRound != -1 then 
            PolPrevotes = rs.Votes.Prevotes(prs.ProposalPOLRound)
            vote = random vote from PolPrevotes the peer does not have  
            Send VoteMessage(vote) to the peer 
            if send returns true, continue

NOTE: if prs is lagging behind (it is in smaller round) why we send them messages from his round. Shouldn't we help
him to catch up in the round where we are? Although we need to be sure that important messages (those with 
Polka are being transmitted). Also, does it make sense sending Prevotes for prs.ProposalPOLRound if we are in higher 
round?           

1b)  if prs.Height != 0 and rs.Height == prs.Height+1 then
        vote = random vote from rs.LastCommit peer does not have  
        Send VoteMessage(vote) to the peer 
        if send returns true, continue
  
1c)  if prs.Height != 0 and rs.Height >= prs.Height+2 then
        Commit = get commit from BlockStore for prs.Height  
        vote = random vote from Commit the peer does not have  
        Send VoteMessage(vote) to the peer 
        if send returns true, continue

2)   Sleep PeerGossipSleepDuration 
```

NOTE: if we are lagging behind peer, we are not forwarding messages to him before we catch up. Can this create a problem
as we are preventing timely communication between peers that might be at the same height/round/step and are connected 
over peers that are lagging behind?
NOTE: We should probably handle gossiping logic at one place in a uniform way.

## QueryMaj23Routine

It is used to send the following message: `VoteSetMaj23Message`. `VoteSetMaj23Message` is sent to indicate that a given 
BlockID has seen +2/3 votes. This routine is based on the local round state (denoted rs) and the known round state of 
the peer (denotes prs). The routine repeats forever the logic shown below. 

```
1a) if rs.Height == prs.Height then
        Prevotes = rs.Votes.Prevotes(prs.Round)
        if there is a ⅔ majority for some blockId in Prevotes then
        m = VoteSetMaj23Message(prs.Height, prs.Round, Prevote, blockId)
        Send m to peer
        Sleep PeerQueryMaj23SleepDuration

1b) if rs.Height == prs.Height then
        Precommits = rs.Votes.Precommits(prs.Round)
        if there is a ⅔ majority for some blockId in Precommits then
        m = VoteSetMaj23Message(prs.Height,prs.Round,Precommit,blockId)
        Send m to peer
        Sleep PeerQueryMaj23SleepDuration

1c) if rs.Height == prs.Height and prs.ProposalPOLRound >= 0 then
        Prevotes = rs.Votes.Prevotes(prs.ProposalPOLRound)
        if there is a ⅔ majority for some blockId in Prevotes then
        m = VoteSetMaj23Message(prs.Height,prs.ProposalPOLRound,Prevotes,blockId)
        Send m to peer
        Sleep PeerQueryMaj23SleepDuration

1d) if prs.CatchupCommitRound != -1 and 0 < prs.Height and 
        prs.Height <= blockStore.Height() then 
        Commit = LoadCommit(prs.Height)
        m = VoteSetMaj23Message(prs.Height,Commit.Round,Precommit,Commit.blockId)
        Send m to peer
        Sleep PeerQueryMaj23SleepDuration

2)  Sleep PeerQueryMaj23SleepDuration
```

## Broadcast routine

When consensus reactor is started it starts the broadcast routine. 
The Broadcast routine subscribes to internal event buss ro receive new round steps, votes messages and proposal
heartbeat messages, and starts a go routine to broadcasts events to peers upon receiving them.
It brodcasts `NewRoundStepMessage` or `CommitStepMessage` upon new round state event. Note that
broadcasting these messages does not depend on peer state. It is sent over `StateChannel`. Upon receiving VoteMessage 
it broadcasts `HasVoteMessage` message to its peers over `StateChannel`. `ProposalHeartbeatMessage` is sent the same way
over `StateChannel`.

NOTE: We don't check what is the peer state when we send messages in Broadcast routine and we don't remember what 
messages we have sent.

## Individual message sending

When a process receives `VoteSetMaj23Message` message, it responds with a VoteSetBitsMessage showing which votes we have
(and consequently shows which we don't have). This message is send on `VoteSetBitsChannel`.


 


 
 

    


    



  


