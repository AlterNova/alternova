use starknet::ContractAddress;

#[starknet::interface]
trait IAlterNova<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
    fn safe_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn approve(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn get_approved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;

    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn ownerOf(self: @TContractState, tokenId: u256) -> ContractAddress;
    fn safeTransferFrom(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        tokenId: u256,
        data: Span<felt252>
    );
    fn transferFrom(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, tokenId: u256
    );
    fn setApprovalForAll(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn getApproved(self: @TContractState, tokenId: u256) -> ContractAddress;
    fn isApprovedForAll(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;

    fn baseURI(self: @TContractState) -> Array<felt252>;
    fn updateBaseURI(ref self: TContractState, baseURI: Array<felt252>);
    fn updateMintPrice(ref self: TContractState, mintPrice: u256);
    fn getMintPrice(self: @TContractState, amount: u256) -> u256;
    fn updateSaleStartTimestamp(ref self: TContractState, _saleStartTimestamp: u64);
    fn updateRevealTimestamp(ref self: TContractState, _revealTimestamp: u64);
    fn updateMaxSupply(ref self: TContractState, maxSupply: u256);
    fn freeMintAn(ref self: TContractState);
    fn mintAN(ref self: TContractState, amount: u256);
    fn admintMintAN(ref self: TContractState, amount: u256);
    fn getTokenIds(self: @TContractState, user: ContractAddress) -> Array<u256>;
    fn getOwnersOf(self: @TContractState, tokenIds: Array<u256>) -> Array<ContractAddress>;
    fn withdrawTokens(ref self: TContractState, token: ContractAddress, amount: u256);
    fn tokenURI(self: @TContractState, tokenId: u256) -> Array<felt252>;
    fn token_uri(self: @TContractState, tokenId: u256) -> Array<felt252>;
    fn nfthash(self: @TContractState) -> Array<felt252>;
    fn totalSupply(self: @TContractState) -> u256;
    fn saleStartTimestamp(self: @TContractState) -> u64;
    fn revealTimestamp(self: @TContractState) -> u64;
    fn maxSupply(self: @TContractState) -> u256;
    fn remainingToAssign(self: @TContractState) -> u256;
    fn freeMintDone(self: @TContractState, user: ContractAddress) -> bool;
    fn updateOwner(ref self: TContractState, newOwner: ContractAddress);
}

#[starknet::contract]
mod AlterNova {
    use core::traits::AddEq;
    use core::to_byte_array::AppendFormattedToByteArray;
    use openzeppelin::token::erc721::interface::IERC721CamelOnly;
    use core::array::ArrayTrait;
    use alternova::IAlterNova;
    use core::box::BoxTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use core::traits::Into;
    use openzeppelin::token::erc721::erc721::ERC721Component::InternalTrait;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use openzeppelin::token::erc20::dual20::DualCaseERC20Trait;
    use openzeppelin::token::erc20::dual20::DualCaseERC20;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::get_block_timestamp;
    use starknet::get_block_info;
    use starknet::get_tx_info;
    use core::hash::HashStateExTrait;
    use hash::{HashStateTrait, Hash};
    use pedersen::{PedersenTrait, HashState};
    use custom_uri::{interface::IInternalCustomURI, main::custom_uri_component};

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: custom_uri_component, storage: custom_uri, event: CustomUriEvent);

    // SRC5
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        custom_uri: custom_uri_component::Storage,
        owner: ContractAddress,
        mintPrice: u256,
        saleStartTimestamp: u64,
        revealTimestamp: u64,
        maxSupply: u256,
        assignOrders: LegacyMap<u256, u256>,
        paymentTokenAddress: ContractAddress,
        totalSupply: u256,
        anRemainingToAssign: u256,
        holderTokensLen: LegacyMap<ContractAddress, u32>, // address -> len
        holderTokens: LegacyMap<(ContractAddress, u32), u256>, // address, index -> tokenID
        holderTokensMap: LegacyMap<(ContractAddress, u256), u32>, // address, tokenID -> index
        freeMinters: LegacyMap<ContractAddress, bool>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        CustomUriEvent: custom_uri_component::Event
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        paymentTokenAddress: ContractAddress,
        saleStartTimestamp: u64,
        revealTimestamp: u64,
    ) {
        let name = 'AlterNova';
        let symbol = 'AN';
        self.owner.write(owner);
        self.erc721.initializer(name, symbol);
        self.paymentTokenAddress.write(paymentTokenAddress);
        self.saleStartTimestamp.write(saleStartTimestamp);
        self.revealTimestamp.write(revealTimestamp);
        self.totalSupply.write(0);
        self.anRemainingToAssign.write(10000);
        self.maxSupply.write(10000);
        self.mintPrice.write(25000000000000000000);

        let mut baseUri: Array<felt252> = ArrayTrait::new();
        baseUri.append('https://anovastark.s3.amazonaws');
        baseUri.append('.com/assets/');
        self._setBaseURI(baseUri);
    }

    mod Errors {
        const INVALID_TOKEN_ID: felt252 = 'ERC721: invalid token ID';
        const INVALID_ACCOUNT: felt252 = 'ERC721: invalid account';
        const UNAUTHORIZED: felt252 = 'ERC721: unauthorized caller';
    }

    #[abi(embed_v0)]
    impl AlterNovaImpl of super::IAlterNova<ContractState> {
        fn updateOwner(ref self: ContractState, newOwner: ContractAddress) {
            self._verifyAdmin();
            self.owner.write(newOwner);
        }

        /// Returns the number of NFTs owned by `account`.
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            assert(!account.is_zero(), Errors::INVALID_ACCOUNT);
            self.erc721.ERC721_balances.read(account)
        }

        /// Returns the owner address of `token_id`.
        ///
        /// Requirements:
        ///
        /// - `token_id` exists.
        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721._owner_of(token_id)
        }

        /// Transfers ownership of `token_id` from `from` if `to` is either an account or `IERC721Receiver`.
        ///
        /// `data` is additional data, it has no specified format and it is sent in call to `to`.
        ///
        /// Requirements:
        ///
        /// - Caller is either approved or the `token_id` owner.
        /// - `to` is not the zero address.
        /// - `from` is not the zero address.
        /// - `token_id` exists.
        /// - `to` is either an account contract or supports the `IERC721Receiver` interface.
        ///
        /// Emits a `Transfer` event.
        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            assert(
                self.erc721._is_approved_or_owner(get_caller_address(), token_id),
                Errors::UNAUTHORIZED
            );
            self.erc721._safe_transfer(from, to, token_id, data);
            self._transferHolderAdjust(token_id, from, to);
        }

        /// Transfers ownership of `token_id` from `from` to `to`.
        ///
        /// Requirements:
        ///
        /// - Caller is either approved or the `token_id` owner.
        /// - `to` is not the zero address.
        /// - `from` is not the zero address.
        /// - `token_id` exists.
        ///
        /// Emits a `Transfer` event.
        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            assert(
                self.erc721._is_approved_or_owner(get_caller_address(), token_id),
                Errors::UNAUTHORIZED
            );
            self.erc721._transfer(from, to, token_id);
            self._transferHolderAdjust(token_id, from, to);
        }

        /// Change or reaffirm the approved address for an NFT.
        ///
        /// Requirements:
        ///
        /// - The caller is either an approved operator or the `token_id` owner.
        /// - `to` cannot be the token owner.
        /// - `token_id` exists.
        ///
        /// Emits an `Approval` event.
        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let owner = self.erc721._owner_of(token_id);

            let caller = get_caller_address();
            assert(
                owner == caller || self.is_approved_for_all(owner, caller), Errors::UNAUTHORIZED
            );
            self.erc721._approve(to, token_id);
        }

        /// Enable or disable approval for `operator` to manage all of the
        /// caller's assets.
        ///
        /// Requirements:
        ///
        /// - `operator` cannot be the caller.
        ///
        /// Emits an `Approval` event.
        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            self.erc721._set_approval_for_all(get_caller_address(), operator, approved)
        }

        /// Returns the address approved for `token_id`.
        ///
        /// Requirements:
        ///
        /// - `token_id` exists.
        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            assert(self.erc721._exists(token_id), Errors::INVALID_TOKEN_ID);
            self.erc721.ERC721_token_approvals.read(token_id)
        }

        /// Query if `operator` is an authorized operator for `owner`.
        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.erc721.ERC721_operator_approvals.read((owner, operator))
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn ownerOf(self: @ContractState, tokenId: u256) -> ContractAddress {
            self.owner_of(tokenId)
        }

        fn safeTransferFrom(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            tokenId: u256,
            data: Span<felt252>
        ) {
            self.safe_transfer_from(from, to, tokenId, data)
        }

        fn transferFrom(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, tokenId: u256
        ) {
            self.transfer_from(from, to, tokenId)
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            self.set_approval_for_all(operator, approved)
        }

        fn getApproved(self: @ContractState, tokenId: u256) -> ContractAddress {
            self.get_approved(tokenId)
        }

        fn isApprovedForAll(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.is_approved_for_all(owner, operator)
        }

        fn baseURI(self: @ContractState) -> Array<felt252> {
            self.custom_uri.get_base_uri()
        }

        fn updateBaseURI(ref self: ContractState, baseURI: Array<felt252>) {
            self._verifyAdmin();
            self._setBaseURI(baseURI);
        }

        fn updateMintPrice(ref self: ContractState, mintPrice: u256) {
            self._verifyAdmin();
            self.mintPrice.write(mintPrice);
        }

        fn getMintPrice(self: @ContractState, amount: u256) -> u256 {
            amount * self.mintPrice.read()
        }

        fn updateSaleStartTimestamp(ref self: ContractState, _saleStartTimestamp: u64) {
            self._verifyAdmin();
            assert(get_block_timestamp() < self.saleStartTimestamp.read(), 'Mint already started');
            self.saleStartTimestamp.write(_saleStartTimestamp);
        }

        fn updateRevealTimestamp(ref self: ContractState, _revealTimestamp: u64) {
            self._verifyAdmin();
            self.revealTimestamp.write(_revealTimestamp);
        }

        fn updateMaxSupply(ref self: ContractState, maxSupply: u256) {
            self._verifyAdmin();
            self.maxSupply.write(maxSupply);
        }

        fn withdrawTokens(ref self: ContractState, token: ContractAddress, amount: u256) {
            let token = DualCaseERC20 { contract_address: token };
            token.transfer_from(get_contract_address(), self.owner.read(), amount);
        }

        fn freeMintAn(ref self: ContractState) {
            assert(get_block_timestamp() >= self.saleStartTimestamp.read(), 'Sale not started');
            let caller = get_caller_address();
            let currentSupply = self.totalSupply.read();
            assert(currentSupply >= 200 && currentSupply < 1000, 'Free mint not possible');
            assert(!self.freeMinters.read(caller), 'Wallet already minted free nft');
            self._mintAN(1, caller, true);
            self.freeMinters.write(caller, true);
        }

        fn mintAN(ref self: ContractState, amount: u256) {
            assert(get_block_timestamp() >= self.saleStartTimestamp.read(), 'Sale not started');
            assert(amount <= 20, 'Cant mint more than 20 at once');
            let mintCost = self.getMintPrice(amount);
            let caller = get_caller_address();
            let token = DualCaseERC20 { contract_address: self.paymentTokenAddress.read() };
            let callerBalance = token.balance_of(caller);
            let currentSupply = self.totalSupply.read();

            assert(currentSupply >= 1000, 'Free mint ongoing');
            assert(callerBalance > mintCost, 'Not enough tokens to mint');

            token.transfer_from(caller, self.owner.read(), mintCost);
            self._mintAN(amount, caller, true);
        }

        fn admintMintAN(ref self: ContractState, amount: u256) {
            self._verifyAdmin();
            let currentSupply = self.totalSupply.read();
            let caller = get_caller_address();
            assert(currentSupply < 200, 'Admin mint finished.');

            self._mintAN(amount, caller, true);
        }

        fn getTokenIds(self: @ContractState, user: ContractAddress) -> Array<u256> {
            let anBalance = self.erc721.balanceOf(user);

            let mut tokenIds: Array<u256> = ArrayTrait::new();
            let holderTokensLen = self.holderTokensLen.read(user);
            let mut i = 0_u32;
            loop {
                if i >= holderTokensLen {
                    break;
                }

                tokenIds.append(self.holderTokens.read((user, i)));
                i += 1
            };

            return tokenIds;
        }

        fn getOwnersOf(self: @ContractState, tokenIds: Array<u256>) -> Array<ContractAddress> {
            let mut owners: Array<ContractAddress> = ArrayTrait::new();
            let mut i = 0;
            loop {
                if i >= tokenIds.len() {
                    break;
                }

                owners.append(self.ownerOf(*tokenIds.at(i)));
            };

            return owners;
        }

        fn tokenURI(self: @ContractState, tokenId: u256) -> Array<felt252> {
            self.token_uri(tokenId)
        }

        fn token_uri(self: @ContractState, tokenId: u256) -> Array<felt252> {
            assert(self.erc721._exists(tokenId), 'TokenId does not exist');
            let mut output: Array<felt252> = ArrayTrait::new();

            let base = self.custom_uri.get_uri(tokenId);
            let mut last_i = base.len() - 1;
            let last = *base.at(last_i);
            let mut i = 0;
            loop {
                if i == last_i {
                    break;
                }
                output.append(*base.at(i));
                i += 1;
            };
            _append_to_str(ref output, last.into(), array!['.', 'j', 's', 'o', 'n'].span());
            return output;
        }

        fn nfthash(self: @ContractState) -> Array<felt252> {
            let mut hash: Array<felt252> = ArrayTrait::new();
            hash.append('4abab7e1ad76d1d5c35fc6375d48f63');
            hash.append('4db3a18fa66aaa052537ac08ceefd14');
            hash.append('ad');

            hash
        }

        fn totalSupply(self: @ContractState) -> u256 {
            self.totalSupply.read()
        }

        fn saleStartTimestamp(self: @ContractState) -> u64 {
            self.saleStartTimestamp.read()
        }

        fn revealTimestamp(self: @ContractState) -> u64 {
            self.revealTimestamp.read()
        }

        fn maxSupply(self: @ContractState) -> u256 {
            self.maxSupply.read()
        }

        fn remainingToAssign(self: @ContractState) -> u256 {
            self.anRemainingToAssign.read()
        }

        fn freeMintDone(self: @ContractState, user: ContractAddress) -> bool {
            self.freeMinters.read(user)
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _setBaseURI(ref self: ContractState, _baseURI: Array<felt252>) {
            self.custom_uri.set_base_uri(_baseURI.span());
        }

        fn _verifyAdmin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Invalid caller');
        }

        fn _random(self: @ContractState) -> u256 {
            let blocktimestamp: u256 = get_block_timestamp().into();
            let blocknumber: u256 = get_block_info().unbox().block_number.into();
            let blockhash: felt252 = get_tx_info().unbox().transaction_hash.into();
            let txnNonce: u256 = get_tx_info().unbox().nonce.into();
            let caller = get_caller_address();

            let txnHash = PedersenTrait::new(0);
            let txnHash256: u256 = txnHash.update_with(blockhash).finalize().into()
                / blocktimestamp;

            let addressHash = PedersenTrait::new(0);
            let addressHash256: u256 = addressHash.update_with(caller).finalize().into()
                / blocktimestamp;

            let dataSum = blocktimestamp + blocknumber + txnNonce + txnHash256 + addressHash256;

            let finalHash = PedersenTrait::new(0);
            let finalHash256: u256 = finalHash.update_with(dataSum).finalize().into();

            return finalHash256 / self.anRemainingToAssign.read();
        }

        fn _fillAssignOrder(ref self: ContractState, orderA: u256, orderB: u256) -> u256 {
            let mut temp: u256 = orderA;
            if self.assignOrders.read(orderA) > 0 {
                temp = self.assignOrders.read(orderA);
            }
            self.assignOrders.write(orderA, orderB);

            if self.assignOrders.read(orderB) > 0 {
                self.assignOrders.write(orderA, self.assignOrders.read(orderB));
            }
            self.assignOrders.write(orderB, temp);

            self.assignOrders.read(orderA)
        }

        fn _mintAN(ref self: ContractState, amount: u256, address: ContractAddress, random: bool) {
            let currentSupply = self.totalSupply.read();
            let finalSupply = currentSupply + amount;
            let maxSupply = self.maxSupply.read();
            assert(finalSupply <= maxSupply, 'Cannot mint more');
            let mut i: u256 = 0;
            let data: Array<felt252> = ArrayTrait::new();
            let mut anRemainingToAssign = self.anRemainingToAssign.read();
            let mut holderTokensLen = self.holderTokensLen.read(address);
            loop {
                if i >= amount {
                    break;
                }
                let mut randIndex: u256 = currentSupply % anRemainingToAssign;
                if random {
                    randIndex = self._random() % anRemainingToAssign;
                }

                anRemainingToAssign -= 1;
                let anIndex = self._fillAssignOrder(anRemainingToAssign, randIndex);

                self.erc721._safe_mint(address, anIndex, data.span());
                self.holderTokens.write((address, holderTokensLen), anIndex);
                self.holderTokensMap.write((address, anIndex), holderTokensLen);

                i += 1_u256;
                holderTokensLen += 1_u32;
            };

            self.totalSupply.write(currentSupply + amount);
            self.holderTokensLen.write(address, holderTokensLen);
            self.anRemainingToAssign.write(anRemainingToAssign);
        }

        fn _transferHolderAdjust(
            ref self: ContractState, token_id: u256, from: ContractAddress, to: ContractAddress
        ) {
            let fromHolderTokensLen = self.holderTokensLen.read(from);
            let toHolderTokensLen = self.holderTokensLen.read(to);

            let anIndexInFromHolderTokens = self.holderTokensMap.read((from, token_id));
            let lastValueInFromHolderTokens = self
                .holderTokens
                .read((from, fromHolderTokensLen - 1));

            self.holderTokens.write((from, fromHolderTokensLen - 1), 9999999);
            self.holderTokens.write((from, anIndexInFromHolderTokens), lastValueInFromHolderTokens);

            self.holderTokens.write((to, toHolderTokensLen), token_id);
            self.holderTokensMap.write((to, token_id), toHolderTokensLen);

            self.holderTokensLen.write(from, fromHolderTokensLen - 1);
            self.holderTokensLen.write(to, toHolderTokensLen + 1);
        }
    }

    fn _append_to_str(ref str: Array<felt252>, last_field: u256, to_add: Span<felt252>) {
        let mut free_space: usize = 0;
        let ascii_length: NonZero<u256> = 256_u256.try_into().unwrap();
        let mut i = 0;
        let mut shifted_field = last_field;
        // find free space in last text field
        loop {
            let (_shifted_field, char) = DivRem::div_rem(shifted_field, ascii_length);
            shifted_field = _shifted_field;
            if char == 0 {
                free_space += 1;
            } else {
                free_space = 0;
            };
            i += 1;
            if i == 31 {
                break;
            }
        };

        let mut new_field = 0;
        let mut shift = 1;
        let mut i = free_space;
        // add digits to the last text field
        loop {
            if free_space == 0 {
                break;
            }
            free_space -= 1;
            match to_add.get(free_space) {
                Option::Some(c) => {
                    new_field += shift * *c.unbox();
                    shift *= 256;
                },
                Option::None => {}
            };
        };
        new_field += last_field.try_into().expect('invalid string') * shift;
        str.append(new_field);
        if i >= to_add.len() {
            return;
        }

        let mut new_field_shift = 1;
        let mut new_field = 0;
        let mut j = i + 30;
        // keep adding digits by chunks of 31
        loop {
            match to_add.get(j) {
                Option::Some(char) => {
                    new_field += new_field_shift * *char.unbox();
                    if new_field_shift == 0x100000000000000000000000000000000000000000000000000000000000000 {
                        str.append(new_field);
                        new_field_shift = 1;
                        new_field = 0;
                    } else {
                        new_field_shift *= 256;
                    }
                },
                Option::None => {},
            }
            if j == i {
                i += 31;
                j = i + 30;
                str.append(new_field);
                if i >= to_add.len() {
                    break;
                }
                new_field_shift = 1;
                new_field = 0;
            } else {
                j -= 1;
            };
        };
    }
}

