/**
 * T1 Base Contract
 */
contract T1 is Context, Ownable, ERC165, IERC721, IERC721Metadata, IERC721Enumerable, ERC20Recoverable, ERC721Recoverable {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using Strings for uint256;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    // Mapping from holder address to their (enumerable) set of owned tokens
    mapping (address => EnumerableSet.UintSet) private _holderTokens;

    // Enumerable mapping from token ids to their owners
    EnumerableMap.UintToAddressMap private _tokenOwners;

    // Mapping from token ID to approved address
    mapping (uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) private _operatorApprovals;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // ERC721 token contract address serving as "ticket" to flip the bool in additional data
    address private _ticketContract;

    // Base URI
    string private _baseURI;

    // Price per token. Is chosen and can be changed by contract owner.
    uint256 private _tokenPrice;

    struct AdditionalData {
        bool isA; // A (true) or B (false)
        bool someBool; // may be flipped by token owner if he owns T2; default value in _mint
        uint8 power;
    }

    // Mapping from token ID to its additional data
    mapping (uint256 => AdditionalData) private _additionalData;

    // Counter for token id, and types
    uint256 private _nextId = 1;
    uint32 private _countA = 0; // count of B is implicit and not needed

    mapping (address => bool) public freeBoolSetters; // addresses which do not need to pay to set the bool variable

    // limits
    uint256 public constant MAX_SUPPLY = 7000;
    uint32 public constant MAX_A = 1000;
    uint32 public constant MAX_B = 6000;

    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c5
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x095ea7b3 ^ 0x081812fc ^
     *        0xa22cb465 ^ 0xe985e9c5 ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    /*
     *     bytes4(keccak256('name()')) == 0x06fdde03
     *     bytes4(keccak256('symbol()')) == 0x95d89b41
     *     bytes4(keccak256('tokenURI(uint256)')) == 0xc87b56dd
     *
     *     => 0x06fdde03 ^ 0x95d89b41 ^ 0xc87b56dd == 0x5b5e139f
     */
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;

    /*
     *     bytes4(keccak256('totalSupply()')) == 0x18160ddd
     *     bytes4(keccak256('tokenOfOwnerByIndex(address,uint256)')) == 0x2f745c59
     *     bytes4(keccak256('tokenByIndex(uint256)')) == 0x4f6ccce7
     *
     *     => 0x18160ddd ^ 0x2f745c59 ^ 0x4f6ccce7 == 0x780e9d63
     */
    bytes4 private constant _INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor (string memory name, string memory symbol, string memory baseURI, uint256 tokenPrice, address ticketContract) public {
        _name = name;
        _symbol = symbol;
        _baseURI = baseURI;
        _tokenPrice = tokenPrice;
        _ticketContract = ticketContract;

        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_INTERFACE_ID_ERC721);
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
        _registerInterface(_INTERFACE_ID_ERC721_ENUMERABLE);
    }

// public functions:
    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");

        return _holderTokens[owner].length();
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view override returns (address) {
        return _tokenOwners.get(tokenId, "ERC721: owner query for nonexistent token");
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() external view override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(_baseURI, tokenId.toString()));
    }

    /**
    * @dev Returns the base URI set via {_setBaseURI}. This will be
    * automatically added as a prefix in {tokenURI} to each token's URI, or
    * to the token ID if no specific URI is set for that token ID.
    */
    function baseURI() external view returns (string memory) {
        return _baseURI;
    }

    /**
     * @dev Retrieves address of the ticket token contract.
     */
    function ticketContract() external view returns (address) {
        return _ticketContract;
    }

    /**
     * @dev Price per token for public purchase.
     */
    function tokenPrice() external view returns (uint256) {
        return _tokenPrice;
    }

    /**
     * @dev Next token id.
     */
    function nextTokenId() public view returns (uint256) {
        return _nextId;
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view override returns (uint256) {
        require(index < balanceOf(owner), "Invalid token index for holder");
        return _holderTokens[owner].at(index);
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() external view override returns (uint256) {
        // _tokenOwners are indexed by tokenIds, so .length() returns the number of tokenIds
        return _tokenOwners.length();
    }

    /**
     * @dev Supply of A tokens.
     */
    function supplyOfA() external view returns (uint256) {
        return _countA;
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) external view override returns (uint256) {
        require(index < _tokenOwners.length(), "Invalid token index");
        (uint256 tokenId, ) = _tokenOwners.at(index);
        return tokenId;
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) external virtual override {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view override returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) external virtual override {
        require(operator != _msgSender(), "ERC721: approve to caller");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) external virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * @dev Buys a token. Needs to be supplied the correct amount of ether.
     */
    function buyToken() external payable returns (bool)
    {
        uint256 paidAmount = msg.value;
        require(paidAmount == _tokenPrice, "Invalid amount for token purchase");
        address to = msg.sender;
        uint256 nextToken = nextTokenId();
        uint256 remainingTokens = 1 + MAX_SUPPLY - nextToken;
        require(remainingTokens > 0, "Maximum supply already reached");

        _holderTokens[to].add(nextToken);
        _tokenOwners.set(nextToken, to);

        uint256 remainingA = MAX_A - _countA;
        bool a = (uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), now, nextToken))) % remainingTokens) < remainingA;
        uint8 pow = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), now + 1, nextToken))) % (a ? 21 : 79) + (a ? 80 : 1));
        _additionalData[nextToken] = AdditionalData(a, false, pow);

        if (a) {
            _countA = _countA + 1;
        }

        emit Transfer(address(0), to, nextToken);
        _nextId = nextToken.add(1);

        payable(owner()).transfer(paidAmount);
        return true;
    }

    function buy6Tokens() external payable returns (bool)
    {
        uint256 paidAmount = msg.value;
        require(paidAmount == (_tokenPrice * 5 + _tokenPrice / 2), "Invalid amount for token purchase"); // price for 6 tokens is 5.5 times the price for one token
        address to = msg.sender;
        uint256 nextToken = nextTokenId();
        uint256 remainingTokens = 1 + MAX_SUPPLY - nextToken;
        require(remainingTokens > 5, "Maximum supply already reached");
        uint256 endLoop = nextToken.add(6);

        while (nextToken < endLoop) {
            _holderTokens[to].add(nextToken);
            _tokenOwners.set(nextToken, to);

            uint256 remainingA = MAX_A - _countA;
            bool a = (uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), now, nextToken))) % remainingTokens) < remainingA;
            uint8 pow = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), now + 1, nextToken))) % (a ? 21 : 79) + (a ? 80 : 1));
            _additionalData[nextToken] = AdditionalData(a, false, pow);

            if (a) {
                _countA = _countA + 1;
            }

            emit Transfer(address(0), to, nextToken);
            nextToken = nextToken.add(1);
            remainingTokens = remainingTokens.sub(1);
        }

        _nextId = _nextId.add(6);

        payable(owner()).transfer(paidAmount);
        return true;
    }

    /**
     * @dev Retrieves if the specified token is of A type.
     */
    function isA(uint256 tokenId) external view returns (bool) {
        require(_exists(tokenId), "Token ID does not exist");
        return _additionalData[tokenId].isA;
    }

    /**
     * @dev Retrieves if the specified token has its someBool attribute set.
     */
    function someBool(uint256 tokenId) external view returns (bool) {
        require(_exists(tokenId), "Token ID does not exist");
        return _additionalData[tokenId].someBool;
    }

    /**
     * @dev Sets someBool for the specified token. Can only be used by the owner of the token (not an approved account).
     * Owner needs to also own a ticket token to set the someBool attribute.
     */
    function setSomeBool(uint256 tokenId, bool newValue) external {
        require(_exists(tokenId), "Token ID does not exist");
        require(ownerOf(tokenId) == msg.sender, "Only token owner can set attribute");

        if (freeBoolSetters[msg.sender] == false && _additionalData[tokenId].someBool != newValue) {
            require(T2(_ticketContract).burnAnyFrom(msg.sender), "Token owner ticket could not be burned");
        }

        _additionalData[tokenId].someBool = newValue;
    }

    /**
     * @dev Retrieves the power value for a specified token.
     */
    function power(uint256 tokenId) external view returns (uint8) {
        require(_exists(tokenId), "Token ID does not exist");
        return _additionalData[tokenId].power;
    }

// owner functions:
    /**
     * @dev Function to set the base URI for all token IDs. It is automatically added as a prefix to the token id in {tokenURI} to retrieve the token URI.
     */
    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseURI = baseURI_;
    }

    /**
     * @dev Sets a new token price.
     */
    function setTokenPrice(uint256 newPrice) external onlyOwner {
        _tokenPrice = newPrice;
    }

    function setFreeBoolSetter(address holder, bool setForFree) external onlyOwner {
        freeBoolSetters[holder] = setForFree;
    }

// internal functions:
    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) private {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`).
     */
    function _exists(uint256 tokenId) private view returns (bool) {
        return tokenId < _nextId && _tokenOwners.contains(tokenId);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) private view returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - contract owner must have transfer globally allowed.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) private {
        require(ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
        require(to != address(0), "ERC721: transfer to the zero address");

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _holderTokens[from].remove(tokenId);
        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data) private returns (bool)
    {
        if (!to.isContract()) {
            return true;
        }
        bytes memory returndata = to.functionCall(abi.encodeWithSelector(
            IERC721Receiver(to).onERC721Received.selector,
            _msgSender(),
            from,
            tokenId,
            _data
        ), "ERC721: transfer to non ERC721Receiver implementer");
        bytes4 retval = abi.decode(returndata, (bytes4));
        return (retval == _ERC721_RECEIVED);
    }

    function _approve(address to, uint256 tokenId) private {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}
