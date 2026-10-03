class IndexedSet {
    constructor() {
        this._items = [];
        this._itemSet = new Set();
        this._indexMap = new Map();
    }
    insertAt(index, elements) {
        let newElements;
        if (elements.length <= 100) {
            newElements = elements.filter((e, i, arr) => !this._itemSet.has(e) && arr.indexOf(e) === i);
        }
        else {
            const seen = new Set();
            newElements = [];
            for (let i = 0; i < elements.length; i++) {
                const e = elements[i];
                if (!this._itemSet.has(e) && !seen.has(e)) {
                    seen.add(e);
                    newElements.push(e);
                }
            }
        }
        if (newElements.length === 0)
            return;
        const insertIndex = Math.max(0, Math.min(index, this._items.length));
        if (insertIndex === this._items.length) {
            for (let i = 0; i < newElements.length; i++) {
                const element = newElements[i];
                this._indexMap.set(element, this._items.length);
                this._items.push(element);
                this._itemSet.add(element);
            }
            return;
        }
        if (insertIndex === 0) {
            for (let i = 0; i < this._items.length; i++) {
                this._indexMap.set(this._items[i], i + newElements.length);
            }
            if (newElements.length <= 10000) {
                this._items.splice(0, 0, ...newElements);
            }
            else {
                this._chunkedInsert(0, newElements);
            }
            for (let i = 0; i < newElements.length; i++) {
                this._itemSet.add(newElements[i]);
                this._indexMap.set(newElements[i], i);
            }
            return;
        }
        for (let i = this._items.length - 1; i >= insertIndex; i--) {
            this._indexMap.set(this._items[i], i + newElements.length);
        }
        if (newElements.length <= 10000) {
            this._items.splice(insertIndex, 0, ...newElements);
        }
        else {
            this._chunkedInsert(insertIndex, newElements);
        }
        for (let i = 0; i < newElements.length; i++) {
            const element = newElements[i];
            this._itemSet.add(element);
            this._indexMap.set(element, insertIndex + i);
        }
    }
    _chunkedInsert(index, elements) {
        const CHUNK_SIZE = 10000;
        for (let i = 0; i < elements.length; i += CHUNK_SIZE) {
            const chunk = elements.slice(i, i + CHUNK_SIZE);
            this._items.splice(index + i, 0, ...chunk);
        }
    }
    delete(element) {
        if (!this._itemSet.has(element))
            return false;
        const index = this._indexMap.get(element);
        this._items.splice(index, 1);
        this._itemSet.delete(element);
        this._indexMap.delete(element);
        for (let i = index; i < this._items.length; i++) {
            this._indexMap.set(this._items[i], i);
        }
        return true;
    }
    has(element) {
        return this._itemSet.has(element);
    }
    indexOf(element) {
        var _a;
        return (_a = this._indexMap.get(element)) !== null && _a !== void 0 ? _a : -1;
    }
    get(index) {
        return this._items[index];
    }
    get size() {
        return this._items.length;
    }
    [Symbol.iterator]() {
        return this._items[Symbol.iterator]();
    }
    clear() {
        this._items = [];
        this._itemSet.clear();
        this._indexMap.clear();
    }
    find(predicate) {
        return this._items.find(predicate);
    }
}

export { IndexedSet };
