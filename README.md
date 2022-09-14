# Serial Data Task Sequence
The project constitutes minimalistic application which features per cent progress tracking with use of
[`NSURLSessionDataTask`](https://developer.apple.com/documentation/foundation/nsurlsessiondatatask) only (no other NSURLSession tasks are involved in the
implementation of the project.

## Variations
For the sake of wider application of the given sample, there are multiple multiple implementation of `TDWSerialDataTaskSequence` oferring different approaches
on how the data loaded from the remote source is stored:
1. [In-memory storage implementation (tag v0.1.0)](https://github.com/AlexandrSMed/SO-a-73661520-5690248-SerialDataTaskSequence/tree/v0.1.0) - the data is stored in-memory, using `NSData` instance.
2. [Persistent storage implementation (tag v0.1.1)](https://github.com/AlexandrSMed/SO-a-73661520-5690248-SerialDataTaskSequence/tree/v0.1.1) - the data is stored on-disk, using specified file `NSURL`.
