pragma solidity ^0.4.4;


// ERC20 token interface is implemented only partially.
// Token transfer is prohibited due to spec (see PRESALE-SPEC.md),
// hence some functions are left undefined:
//  - transfer, transferFrom,
//  - approve, allowance.

contract PresaleToken {

    /// @dev Constructor
    /// @param _tokenManager Token manager address.
    function PresaleToken(address _tokenManager) {
        tokenManager = _tokenManager;
    }


    /*/
     *  Constants
    /*/
    string public name = "DilationPresaleToken";
    string public symbol = "DPT";
    uint   public decimals = 18;

    uint private PRICE = 200; // 200 DPT per Ether
    uint private TOKEN_SUPPLY_LIMIT = 4000000;


    /*/
     *  Token state
    /*/

    enum Phase {
        Created,
        Running,
        Paused,
        Migrating,
        Migrated
    }
    Phase public currentPhase = Phase.Created;


    uint public totalSupply = 0; // amount of tokens already sold
    mapping (address => uint256) private balance;

    // Token manager has exclusive priveleges to call administrative
    // functions on this contract.
    address private tokenManager;
    // Crowdsale manager has exclusive priveleges to burn presale tokens.
    address public crowdsaleManager;


    modifier onlyTokenManager()     { if(msg.sender != tokenManager) throw; _; }
    modifier onlyCrowdsaleManager() { if(msg.sender != crowdsaleManager) throw; _; }


    /*/
     *  Events
    /*/

    event LogBuy(address indexed owner, uint value);
    event LogBurn(address indexed owner, uint value);
    event LogPhaseSwitch(Phase newPhase);


    /*/
     *  Public functions
    /*/

    /// @dev Lets buy you some tokens.
    function buyTokens() public payable {
        // Available only if presale is running.
        if(currentPhase != Phase.Running) throw;

        if(msg.value == 0) throw;
        uint newTokens = msg.value * PRICE;
        if (totalSupply + newTokens > TOKEN_SUPPLY_LIMIT) throw;
        balance[msg.sender] += newTokens;
        totalSupply += newTokens;
        LogBuy(msg.sender, newTokens);
    }


    /// @dev Returns number of tokens owned by given address.
    /// @param _owner Address of token owner.
    function burnTokens(address _owner) public {
        // Available only during migration phase
        if(currentPhase != Phase.Migrating) throw;

        uint tokens = balance[_owner];
        if(tokens == 0) throw;
        balance[_owner] = 0;
        totalSupply -= tokens;
        LogBurn(_owner, tokens);

        // Automatically switch phase when migration is done.
        if(totalSupply == 0) setPresalePhase(Phase.Migrated);
    }


    /// @dev Returns number of tokens owned by given address.
    /// @param _owner Address of token owner.
    function balanceOf(address _owner) constant returns (uint256) {
        return balance[_owner];
    }


    /*/
     *  Administrative functions
    /*/

    function setPresalePhase(Phase _nextPhase) public
        onlyTokenManager
    {
        bool canSwitchPhase
            =  (currentPhase == Phase.Created && _nextPhase == Phase.Running)
            || (currentPhase == Phase.Running && _nextPhase == Phase.Paused)
                // switch to migration phase only if crowdsale manager is set
            || ((currentPhase == Phase.Running || currentPhase == Phase.Paused)
                && _nextPhase == Phase.Migrating
                && crowdsaleManager != 0x0)
            || (currentPhase == Phase.Paused && _nextPhase == Phase.Running)
            || (currentPhase == Phase.Migrating && _nextPhase == Phase.Migrated
                && totalSupply == 0);

        if(!canSwitchPhase) throw;
        else {
            currentPhase = _nextPhase;
            LogPhaseSwitch(_nextPhase);
        }
    }


    function withdrawEther() public
        onlyTokenManager
    {
        // Available at any phase.
        if(this.balance == 0) {
            if(!tokenManager.send(this.balance)) throw;
        }
    }


    function setCrowdsaleManager(address _mgr) public
        onlyTokenManager
    {
        // You can't change crowdsale contract when migration is in progress.
        if(currentPhase == Phase.Migrating) throw;
        crowdsaleManager = _mgr;
    }


    function selfdestruct() public
        onlyTokenManager
    {
        // Available only if nothing hapened yet or if presale is totally
        // completed.
        if(currentPhase != Phase.Created || currentPhase != Phase.Migrated)
          throw;
        suicide(tokenManager); // send remaining funds to tokenManager
    }
}
