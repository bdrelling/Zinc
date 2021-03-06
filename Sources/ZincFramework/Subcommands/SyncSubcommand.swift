// Copyright © 2019 SpotHero, Inc. All rights reserved.

import CommandHero
import FileHero
import Lumberjack
import ShellRunner

class SyncSubcommand: Subcommand {
    // MARK: - Properties

    // MARK: Command Metadata

    public static var name = "sync"
    public static var usageDescription = "(default) Syncs local files with remote files as defined by a Zincfile."
    public static var arguments: [ArgumentDescribing] = []
    public static var options: [OptionDescribing] = []

    // MARK: Options

    private let file: String?

    // MARK: - Methods

    // MARK: Initializers

    public required init(from parser: ArgumentParser) throws {
        self.file = try parser.valueIfPresent(forOption: "file", shortName: "f")
    }

    // MARK: Subcommand

    public func run() throws {
        try self.sync(self.file)
    }

    // MARK: Utilities

    private func sync(_ filename: String? = nil) throws {
        guard let zincfile = try ZincfileParser.shared.fetch(filename) else {
            return
        }

        // create the temporary directory
        FileClerk.shared.createTempDirectory(deleteExisting: true)

        // // clone the sources
        // for (key, repoURL) in Zincfile.allSources {
        //     // --branch can specify a branch or tag
        //     // --single-branch
        //     var branch = ""
        //     CommandRunner.shared.shell("git clone --branch \(branch) --single-branch \(repoURL) \(FileClerk.tempDirectory)/\(key)")
        // }

        // clone the default repo first
        self.cloneDefaultRepository(zincfile)

        // aggregate the sources into a master dictionary
        self.cloneFileRepositories(zincfile)

        // sync all the files
        self.syncFiles(zincfile)

        // delete the temporary directory
        FileClerk.shared.removeTempDirectory()
    }

    // MARK: Utilities

    private func cloneDefaultRepository(_ zincfile: Zincfile) {
        guard !zincfile.source.isEmpty else {
            Lumberjack.shared.debug("No default repository to sync.")
            return
        }

        Lumberjack.shared.debug("Syncing default source...")

        var url: String

        switch zincfile.source.sourceType {
        case .default:
            // it should be impossible to reach this point
            Lumberjack.shared.report("Default source is empty.")
            return
        case .repository:
            url = "https://github.com/\(zincfile.source).git"
        case .url:
            url = zincfile.source
        case .invalid:
            // TODO: throw error
            return
        }

        let directory = "\(FileClerk.tempDirectory)/default"

        Lumberjack.shared.debug("Cloning default (\(url)) into \(directory)...")

        ShellRunner.shared.gitClone(url,
                                    branch: zincfile.sourceBranch ?? zincfile.sourceTag,
                                    directory: directory)
    }

    private func cloneFileRepositories(_ zincfile: Zincfile) {
        guard !zincfile.files.isEmpty else {
            Lumberjack.shared.report("Error: Files not found.")
            return
        }

        Lumberjack.shared.debug("Cloning sources for \(zincfile.files.count) files...")

        for file in zincfile.files {
            var name: String
            var url: String

            switch file.source.sourceType {
            case .default:
                // nothing to do here if we use the default source for this file
                continue
            case .repository:
                name = file.source
                url = "https://github.com/\(file.source).git"
            case .url:
                name = file.source.repositoryName
                url = file.source
            case .invalid:
                Lumberjack.shared.report("Invalid source: \(file.source)")
                continue
            }

            var directory = "\(FileClerk.tempDirectory)/\(name)"

            if let branch = file.sourceBranch ?? file.sourceTag, !branch.isEmpty {
                directory += "/\(branch)"
            }

            Lumberjack.shared.debug("Cloning \(name) (\(url)) into \(directory)...")

            ShellRunner.shared.gitClone(url,
                                        branch: file.sourceBranch ?? file.sourceTag,
                                        directory: directory)
        }
    }

    private func syncFiles(_ zincfile: Zincfile) {
        Lumberjack.shared.debug("Syncing \(zincfile.files.count) files...")

        // update all files
        for file in zincfile.files {
            // get full source path
            let fullSourcePath = "\(FileClerk.tempDirectory)/\(file.fullSourcePath)"

            // get full destination path
            var fullDestinationPath = file.fullDestinationPath

            // if there's no file name property, use the filename from the source path
            if file.name.isEmpty {
                let filename = FileClerk.shared.filename(for: fullSourcePath)
                fullDestinationPath += "\(filename)"
            }

            // copy file into destination location
            FileClerk.shared.copyItem(from: fullSourcePath, to: fullDestinationPath)
        }
    }
}
